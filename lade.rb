#####
####
###
##
# Lade v1.1
class Lade
#
##
###
####
#####

  require 'rubygems'
  require 'net/http'
  require 'open-uri'
  require 'date'
  require 'cgi'
  
  @@path = File.join(File.dirname(__FILE__), *%w[/])
  
  load @@path+"helper.rb"
  load @@path+"updater.rb"

  @@config_folder_path = @@path+"config/"
  @@downloads_folder_path = @@path+"downloads/"
  @@modules_folder_path = @@path+"modules/"
  @@hosts_folder_path = @@path+"hosts/"
  @@cache_folder_path = @@path+"cache/"
  @@log_folder_path = @@path+"log/"
  
  @@already_downloaded_list_path = @@config_folder_path+"downloaded"
  @@torrent_history_path = @@config_folder_path+"torrent_history"
  @@queue_path = @@config_folder_path+"queue"
  
  def self.load_config
    @@config = FileConfig.getConfig
    @@stopped = @@config["stopped"]
    @@max_concurrent_downloads = @@config["max_concurrent_downloads"] || 1
    @@max_concurrent_downloads = 99 if @@max_concurrent_downloads == 0
    @@extract = @@config["extract"]
    @@require_confirmation = @@config["require_confirm"]
    @@torrent_autoadd_dir = @@config["torrent_autoadd_dir"] || ""
    @@torrent_downloads_dir = @@config["torrent_downloads_dir"] || ""
    
    @@growl_notifications = @@config["growl_notifications"] || false
    @@growl_host = @@config["growl_host"]
    @@growl_port = @@config["growl_port"] || 23053
    @@growl_password = @@config["growl_password"] || ""
    @@notify_on_download_start = @@config["notify_on_download_start"]
    @@notify_on_download_finish = @@config["notify_on_download_finish"]
    @@notify_on_download_confirm = @@config["notify_on_download_confirm"]
  end
  
  def self.prep_directories
    dirs = [@@config_folder_path, @@downloads_folder_path, @@modules_folder_path, @@hosts_folder_path, @@cache_folder_path, @@log_folder_path]
    
    dirs.each { |dir|
      if (!File.directory?(dir))
        begin
          Dir.mkdir(dir)
        rescue StandardError => e
          puts PrettyError.new("Couldn't create necessary folders", e)
          return false
        end
      end
    }
    
    true
  end
  
  def self.concurrent_downloads_count
    processes = `ps ax | grep '\\\-\\\-dejunk'`
    releases_downloading = []
    
    # get filenames from those processes
    processes.lines.each { |process|
      next if process.include?("grep")
      
      process.scan(/\-\-dejunk\s\'(.*?)\'\)/i) { |match|
        filename = match.flatten.first
    
        noextension = filename.gsub(/#{"\\"+File.extname(filename)}$/, "")
        if noextension.match(/\.part\d+$/)
          noextension = noextension.gsub(/#{"\\"+File.extname(noextension)}$/, "")
        end
    
        releases_downloading << noextension
      }
    }
    
    releases_downloading.uniq.count
  end
  
  def self.notify(filename, action_type)
    Lade.load_config
    
    growl_gem_available = Updater.gem_available?("ruby_gntp")
    
    should_notify = [
      @@notify_on_download_start,
      @@notify_on_download_finish,
      @@notify_on_download_confirm][action_type-1]
    should_notify = should_notify && @@growl_notifications
    should_notify = should_notify && !@@growl_host.nil? && !@@growl_host.strip.empty?
    
    if (should_notify && growl_gem_available)
      begin
        require 'ruby_gntp'
        port = ((@@growl_port.nil? || @@growl_port.empty?) ? 23053 : @growl_port.to_i)
        growl = GNTP.new("Lade", @@growl_host, @@growl_password, port)
        growl.register({
          :notifications => [
            {:name => "Download Start"},
            {:name => "Download Finish"},
            {:name => "Download Needs Confirmation"}]
        })
        
        case action_type
        when 1
          name = "Download Start"
          title = "Lade started a download"
        when 2
          name = "Download Finish"
          title = "Lade finished a download"
        when 3
          name = "Download Needs Confirmation"
          title = "Lade needs confirmation to download"
        end
        
        notification = {
          :name => name,
          :title => title,
          :text => filename,
          :icon => @@path+"public/images/Lade.jpg"
        }
        
        growl.notify(notification)
      rescue StandardError => e
        puts PrettyError.new("Couldn't send a Growl notification.", e)
      end
    elsif (should_notify && !growl_gem_available)
      puts "Please restart Lade through Terminal to install the required gem 'ruby_gntp'"
    end
  end
  
  def self.run_modules
    Lade.available_modules.each {
      |mod|
      
      begin
        reason = catch(:reason) {
          Lade.run_module(mod)
          nil
        }
        
        puts reason unless reason.nil?
      rescue StandardError => e
        puts PrettyError.new("There was a problem running the module #{mod}.", e, true)
      end
    }
  end
  
  def self.available_modules
    return Dir.entries(@@modules_folder_path).collect {
      |entry|
      
      entry = entry.capitalize
      (entry.end_with?".rb") ? entry.gsub(".rb", "") : entry if !entry.start_with?"."
    }.compact
  end
  
  def self.run_module(module_name)
    max = @@require_confirmation ? 99 : (@@max_concurrent_downloads - Lade.concurrent_downloads_count)
    if (max < 1)
      throw :reason, "*Already at maximum concurrent downloads. Won't run module #{module_name}."
    end
    
    # Load the module
    puts "Starting module #{module_name}..."
    load @@modules_folder_path+module_name.downcase+".rb"
    module_class = eval("#{module_name}")
    
    if (module_class.respond_to?("broken?"))
      if (module_class.broken?)
        throw :reason, "*Skipping module #{module_name} because it was reported as not working."
      end
    end
    
    # Install the module if first-timer
    if (!@@config["#{module_name.downcase}_installed"])
      puts "First time running #{module_name}. Installing..."
      
      begin
        module_class.install if module_class.respond_to?("install")
      rescue StandardError => e
        puts PrettyError.new(nil, e)
        throw :reason, "Module #{module_name} didn't install correctly."
      end
      
      FileConfig.setValue("#{module_name.downcase}_installed", true)
    end
    
    # Run the always_run method of that module
    begin
      module_class.always_run if module_class.respond_to?"always_run"
    rescue StandardError => e
      puts PrettyError.new(nil, e)
      throw :reason, "Module #{module_name} had a problem running 'always_run'"
    end
    
    
    if (@@stopped)
      throw :reason, "*Lade is disabled. Won't check for new releases."
    end
    
    
    # Now the main method of the module
    result = nil
    to_download = ListFile.new(@@config_folder_path+module_name.downcase)
    already_downloaded = ListFile.new(@@already_downloaded_list_path)
    already_downloaded = already_downloaded.list.collect {
      |item|
      split = item.split(":", 2)
      split.last if split.first == module_name.downcase
    }.compact

    begin
      result = module_class.run(to_download, already_downloaded, max).flatten.compact
    rescue StandardError => e
      puts PrettyError.new(nil, e)
      throw :reason, "There was a problem running the module #{module_name}."
    end
    
    # Update the module's cache
    begin
      if result.empty? && module_class.respond_to?("update_cache")
        module_class.update_cache
        
        # Remove useless entries in the 'downloaded' list now that the cache is up to date
        already_downloaded = ListFile.new(@@already_downloaded_list_path)
        already_downloaded.list = already_downloaded.list.select {
          |item|
          split = item.split(":", 2)
          split.first != module_name.downcase
        }
        already_downloaded.save
      end
    rescue StandardError => e
      puts PrettyError.new(nil, e)
      throw :reason, "Module #{module_name} had a problem updating its cache."
    end
    

    Lade.start_downloads(module_name.downcase, result)
  end
  
  def self.available_hosts
    return Dir.entries(@@hosts_folder_path).select {
      |entry|
      !entry.start_with?"."
    }
  end
  
  def self.load_hosts
    Lade.available_hosts.each {
      |name|
      
      p = @@hosts_folder_path + name
      
      begin
        load p
      rescue StandardError => e
        puts PrettyError.new("Couldn't load host script #{name}", e)
      end 
    }
  end
  
  def self.start_downloads(module_name, groups, from_queue = false)
    groups.each {
      |hash|

      firstfile = hash[:files].first
      group_name = hash[:name] || firstfile[:filename] || firstfile[:download].split("/").last
      group_name = group_name.gsub(/\.((part\d+\.)?rar|zip|torrent)$/, "")
      
      if (@@require_confirmation && !from_queue)
        # add to the queue so that Lade doesn't start the download until it gets confirmation
        hash[:module] = module_name
        hash[:name] = group_name
        YAMLFile.new(@@queue_path) << hash
        puts "'#{group_name}' added to queue and will require confirmation before starting download."
        Lade.notify(group_name, 3)
      else
        links = hash[:files].collect {
          |file|
          
          begin
            filename = file[:filename] || file[:download].split("/").last
            directlink = file[:download] || LinkScanner.get_download_link(file)
            
            raise StandardError.new if directlink.nil?
            
            # give files a more relevant name if available/needed
            filename = filename.gsub(/.*?((\.part\d+)?\.rar|\.zip)/, "#{group_name}"+'\1')
            
            [directlink, filename]
          rescue StandardError => e
            puts PrettyError.new("Couldn't get direct link for file: #{file}", e, true)
            nil
          end
        }.compact

        links.each {
          |directlink, filename|
          self.start_download(directlink, filename)
        }
        
        Lade.notify(group_name, 1)
      end
      
      ListFile.add_and_save(@@already_downloaded_list_path, module_name+":"+hash[:reference])
    }
  end
  
  def self.start_download(directlink, filename, cookie = nil)
    # constructing the command; organized for clarity
    
    primary_cmd = "wget '#{directlink}'"
    con_params = "--continue --no-proxy --timeout 30"
    output_file = "--output-document='#{@@downloads_folder_path}#{filename}'"
    output_log = "--output-file='#{@@log_folder_path}#{filename}.txt'"
    cookie = "--header 'Cookie: #{cookie}'" if cookie

    wget = [primary_cmd, con_params, output_file, output_log, cookie].compact.join(" ")
    
    dl_finish_call = "ruby #{@@path}lade.rb --dejunk '#{filename}'"
    silencer = ">/dev/null 2>&1 &"

    cmd = "(#{wget} && #{dl_finish_call}) #{silencer}"
      
    `#{cmd}`
    
    puts "Direct download started."
  end
  
  def self.clean_up
    Updater.update_broken_modules_list

    Dir.entries(@@log_folder_path).each {
      |file|
      
      next if (file == ".") || (file == "..")
      
      # delete log file if older than 2 days
      if ((Time.now - File.mtime("#{@@log_folder_path}#{file}") > 60*60*24*2) || file.start_with?("."))
        begin
          File.delete("#{@@log_folder_path}#{file}")
        rescue StandardError => e
          puts PrettyError.new("Couldn't delete log file.", e)
        end
      end
    }
    
    # Remove hidden/OSX files
    Dir.entries(@@downloads_folder_path).each {
      |file|
      
      next if (file == ".") || (file == "..")
      File.delete("#{@@downloads_folder_path}#{file}") if file.start_with?"."
    }
    
    # Remove entries older than 24h from torrent_history
    torrent_history = ListFile.new(@@torrent_history_path)
    last_24h_timestamp = Time.now.to_i - (24*3600)
    torrent_history.list = torrent_history.list.select {
      |item|
      time = item.split(":", 2).last
      
      ((time.to_i == 0) || (time.to_i > last_24h_timestamp))
    }
    torrent_history.save
  end
  
  def self.log
    orig_stdout = $stdout
    $stdout = File.new("#{@@log_folder_path}#{Time.now.strftime("%Y%m%d-h%H")}.txt", "a")
    $stdout.sync = true
    puts "@ #{Time.now.to_s}\n\n"
    yield
  ensure
    puts "\n"
    $stdout = orig_stdout
    $stdout.sync = true
  end
  
  def self.dejunk
    Lade.load_config
    
    Lade.log do
      puts "Dejunk started..."
      filename = (ARGV[0] == "--dejunk" ? ARGV[1] : nil)
      if (filename)
        puts "#{filename} just finished downloading. Processing downloads..."
        
        if (!filename.end_with?(".zip") && !filename.end_with?(".rar") && !filename.end_with?(".torrent"))
          Lade.notify(filename, 2)
        end
      end
      
      torrent_configured = !@@torrent_autoadd_dir.empty? && File.directory?(@@torrent_autoadd_dir)
      torrent_downloads_move = (torrent_configured && !@@torrent_downloads_dir.empty? && File.directory?(@@torrent_downloads_dir))
      
      if (!(@@extract || torrent_configured))
        puts "Nothing to do."
        break
      end
      
      # Move finished torrent downloads to Lade's downloads folder
      if (torrent_downloads_move)
        ListFile.new(@@torrent_history_path).list.each {
          |line|
          torrent_filename = line.split(":", 2).first
          torrent_filename = torrent_filename.gsub(/\.torrent$/, "")
          
          downloaded_file = @@torrent_downloads_dir+torrent_filename
          
          to_move = []
          
          if (File.exist?(downloaded_file))
            # file with given torrent filename exists, let's move that
            to_move << downloaded_file
          else
            # file with given torrent filename doesn't exists, let's try other extensions
            escaped_for_glob = downloaded_file.gsub(/([\[\]\(\)\?\*])/, '\\\\\1')
            glob_pattern = escaped_for_glob+".*"
            files = Dir.glob(glob_pattern)
            
            files.each {
              |a_file|
              # Skip folders as they have no indication of download status
              # Skip incomplete files
              if (!File.directory?(a_file) && File.extname(a_file) != ".part")
                to_move << a_file
              end
            }
          end
          
          to_move.each {
            |source|
            
            new_name = source.split("/").last
            begin
              File.rename(source, @@downloads_folder_path+new_name)
              puts "'#{source}' moved to '#{@@downloads_folder_path}'"
            rescue StandardError => e
              msg = "Couldn't move '#{source}' to '#{@@downloads_folder_path}'"
              puts PrettyError.new(msg, e)
            end
          }
        }
      end
      
      archives = [] # .rar/.zip files needing extraction
      torrents = [] # .torrent files needing moving from downloads to autoadd folder
      
      # See if we have any archives/.torrent that need extracting/moving
      (Dir.entries @@downloads_folder_path).each {
        |entry|
        
        next if entry.start_with?"."
        
        ps = `ps ax | grep wget`.to_s
        
        is_rar = (entry =~ /\.rar$/i)
        is_multipart = (entry =~ /\.part\d+\.rar$/i)
        is_first_part = (entry =~ /\.part0*1\.rar$/i)
        is_zip = (entry =~ /\.zip$/i)
        is_torrent = (entry =~ /\.torrent$/i)
        
        if ((is_rar && !is_multipart) || is_first_part || is_zip)
          no_extension = entry.strip.gsub(/(\.part\d+)?\.rar$/i, "").gsub(/\.zip$/i, "")
          archives << entry if !ps.include?(@@downloads_folder_path+no_extension)
        elsif is_torrent
          torrents << entry if !ps.include?(@@downloads_folder_path+entry)
        end
      }
      
      # Move the .torrent files
      if (torrent_configured)
        moved = []
        @@torrent_autoadd_dir += "/" unless @@torrent_autoadd_dir.end_with?"/"
        torrents.each {
          |torrent|
          
          begin
            File.rename(@@downloads_folder_path+torrent, @@torrent_autoadd_dir+torrent)
            moved << "#{torrent}:#{Time.now.to_i}:0"
            puts "'#{torrent}' moved to '#{@@torrent_autoadd_dir}'"
          rescue StandardError => e
            puts PrettyError.new("Couldn't move #{torrent}", e)
          end
        }
        
        ListFile.add_and_save(@@torrent_history_path, moved)
      end
      
      # Extract the archives
      if (@@extract)
        puts "****************\nExtraction time!\n****************\n"
        puts "No files to extract." if archives.count == 0

        archives.each {
          |archive|
          
          next unless File.exist?(@@downloads_folder_path+archive)
          
          if (Lade.extract(archive) == 0)
            puts "Extraction succeeded."
            
            no_extension = archive.gsub(/(\.part\d+)?\.rar$/i, "").gsub(/\.zip$/i, "")
            extraction_folder = @@downloads_folder_path+no_extension
            
            Lade.notify(no_extension, 2)
            
            # remove all related .rar files from downloads folder
            (Dir.entries @@downloads_folder_path).each { |file|
              if (file.start_with?("#{no_extension}.") && (file.end_with?(".rar") || file.end_with?(".rar_extracted") || file.end_with?(".zip") || file.end_with?(".zip_extracted")))
                File.delete("#{@@downloads_folder_path}#{file}")
                puts "'#{file}' removed."
              end
            }
            
            # move interesting files, remove the others
            (Dir.entries extraction_folder).each { |file|
              next if (file == ".." || file == ".")
              
              is_directory = File.directory?(extraction_folder+"/"+file)
              extension = File.extname(file)
              extensions_to_keep = [".srt", ".sub", ".idx", ".ass", ".ssa", ".iso", ".nfo", ".zip", ".rar"]
              
              # special cleaning for files downloaded by module 'Shows'
              one = "?_?)moc.\\:?(daerhtesaeler?_".reverse
              cleaned_filename = file.gsub(/#{one}/im, "")
              
              if ((extensions_to_keep.include?extension) || (File.new("#{extraction_folder}/#{file}").size >= (1024*128)) || is_directory)
                
                File.rename(
                "#{extraction_folder}/#{file}",
                "#{@@downloads_folder_path}#{cleaned_filename}")
                puts "'#{cleaned_filename}' moved to 'Downloads'"
                next
              end
            
              File.delete("#{extraction_folder}/#{file}")
              puts "'#{extraction_folder.split("/").last}/#{file}' removed."
            }
            
            # remove extraction directory if empty
            begin
              Dir.delete(extraction_folder)
              puts "Folder '#{extraction_folder.split("/").last}' removed."
            rescue StandardError => e
              puts PrettyError.new("Couldn't delete temporary extraction folder #{extraction_folder}.", e)
            end
          end
        }
      end
      
      puts "Dejunk finished."
    end
  end
  
  def self.extract(archive)
    puts "Extracting #{archive}..."
    no_extension = archive.gsub(/(\.part\d+)?\.rar$/i, "").gsub(/\.zip$/i, "")
    
    extraction_folder = @@downloads_folder_path+no_extension
    Dir.mkdir extraction_folder if !File.directory? extraction_folder
    
    archive_path = @@downloads_folder_path+archive
    new_name = archive_path+"_extracted"
    failure_name = archive_path+"_failed"
    tmp_log = archive_path+"_extract.log"
    
    if File.exists?(tmp_log)
      puts "#{no_extension} is already being extracted by another Lade process. Skipping..."
      return 1
    end
    
    cmd = "unrar e '#{archive_path}' '#{extraction_folder}' > '#{tmp_log}' 2>&1"
    zip_cmd = "unzip -o '#{archive_path}' -d '#{extraction_folder}' > '#{tmp_log}' 2>&1"
    
    archive =~ /\.zip$/i ? `#{zip_cmd}` : `#{cmd}`
    
    extraction_result = $?.to_i
    
    File.rename(archive_path, new_name) # add _extracted to part1.rar

    if (extraction_result != 0)
      puts "Failed extraction."
      
      # append the extraction log to unrar-error.log
      log = nil
      File.open(tmp_log, "r") do |f|
        log = f.read
      end
    
      File.open(@@downloads_folder_path+"unrar-error.log", "a") do |f|
        f.write("
        **************************\n
        #{archive} extract attempt @ #{Time.now.to_s}\n
        **************************\n
        #{log}
        \n\n\n\n\n\n")
      end
      
      File.rename(new_name, failure_name)
    end
    
    File.delete(tmp_log)
    
    extraction_result
  end
  
  def self.main
    if (!Lade.prep_directories)
      puts "Couldn't continue."
      return
    end
    
    Lade.load_config
    
    Lade.log do
      Lade.clean_up

      Lade.load_hosts
      Lade.run_modules
    end
    
    Lade.dejunk
  end
end

Lade.dejunk if ARGV[0] == "--dejunk"