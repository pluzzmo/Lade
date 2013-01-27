#####
####
###
##
# Lade v1.0
class Lade
#
##
###
####
#####

#####
## Configuration
#####
  ### smartphone notifications
  ## windows phone
  @@notifywp7 = false # true: notifies your windows phone
  @@supertoasty = false
  #false: uses notify my windows phone (notifymywindowsphone.com)
  #true: uses toasty (supertoasty.com)
  @@wpapikey = "" # your supertoasty/nmwp api key
  
#####
## Configuration End
#####

  require 'rubygems'
  require 'net/http'
  require 'open-uri'
  require 'date'
  require 'cgi'
  
  @@path = File.join(File.dirname(__FILE__), *%w[/])
  
  load @@path+"helper.rb"
  load @@path+"jdownloader.rb"
  load @@path+"updater.rb"

  @@config_folder_path = @@path+"config/"
  @@downloads_folder_path = @@path+"downloads/"
  @@modules_folder_path = @@path+"modules/"
  @@hosts_folder_path = @@path+"hosts/"
  @@cache_folder_path = @@path+"cache/"
  @@log_folder_path = @@path+"log/"
  
  @@already_downloaded_list_path = @@config_folder_path+"downloaded"
  @@torrent_history_path = @@config_folder_path+"torrent_history"
  
  def self.load_config
    @@config = FileConfig.getConfig
    @@stopped = @@config["stopped"]
    @@max_concurrent_downloads = @@config["max_concurrent_downloads"] || 1
    @@max_concurrent_downloads = 99 if @@max_concurrent_downloads == 0
    @@extract = @@config["extract"]
    @@jdremote = @@config["jdremote"]
    @@torrent_autoadd_dir = @@config["torrent_autoadd_dir"] || ""
    @@torrent_downloads_dir = @@config["torrent_downloads_dir"] || ""
  end
  
  def self.prep_directories
    dirs = [@@config_folder_path, @@downloads_folder_path, @@modules_folder_path, @@hosts_folder_path, @@cache_folder_path, @@log_folder_path]
    
    dirs.each { |dir|
      if (!File.directory?(dir))
        begin
          Dir.mkdir(dir)
        rescue StandardError => e
          puts "Fatal error"
          puts e.to_s
          false
        end
      end
    }
    
    true
  end
  
  def self.is_already_running
    script_filename = File.expand_path(__FILE__).to_s.split("/").last
    processes = `ps ax | grep #{script_filename}`
    
    processes = processes.lines.select { |process|
      process =~ Regexp.new(".*ruby.*"+script_filename.gsub(".", "\\."))
    }
    
    return true if processes.count > 1
    return false
  end
  
  def self.concurrent_downloads_count
    root_folder_name = @@path.split("/").last
    releases_downloading = []
    
    # get wget processes downloading to Lade's folder
    processes = `ps ax | grep wget`
    processes = processes.lines.select { |process|
      process =~ /wget.*#{root_folder_name}/i
    }
    
    # get filenames from those processes
    processes.each { |process|
      process.scan(/wget\s(.*?)\s\-O/i) { |match|
        match = match.first
        match = match.split("/").last # get file name
        match = match.split(".").first # ignore file extensions
        
        releases_downloading << match
      }
    }

    return releases_downloading.uniq.count
  end
  
  def self.notify_smartphone(filename)
    app_name = "Lade"
    description = "#{filename} finished downloading"
    
    if (@@notifywp7)
      if (@@supertoasty)
        url = "http://api.supertoasty.com/notify/#{@@wpapikey}&sender=#{app_name}&title=#{description}&text=#{description}"
      else
        url = "http://notifymywindowsphone.com/publicapi/notify?apikey=#{@@wpapikey}&application=#{app_name}&event=#{description}&description=#{description}"
      end
      
      open url.gsub(" ", "+")
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
        puts "There was a problem running the module #{mod}."
        puts e.to_s
        puts e.backtrace.join("\n")
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
    max = @@max_concurrent_downloads - Lade.concurrent_downloads_count
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
        puts e.to_s
        puts e.backtrace.first
        throw :reason, "Module #{module_name} didn't install correctly."
      end
      
      FileConfig.setValue("#{module_name.downcase}_installed", true)
    end
    
    # Run the always_run method of that module
    begin
      module_class.always_run if module_class.respond_to?"always_run"
    rescue StandardError => e
      puts e.to_s
      puts e.backtrace.first
      throw :reason, "Module #{module_name} had a problem running 'always_run'"
    end
    
    
    if (@@stopped)
      throw :reason, "*Lade is disabled. Won't check for new releases."
    end
    
    
    # Now the main method of the module
    links = nil
    to_download = ListFile.new(@@config_folder_path+module_name.downcase)
    already_downloaded = ListFile.new(@@already_downloaded_list_path)
    already_downloaded = already_downloaded.list.collect {
      |item|
      split = item.split(":", 2)
      split.last if split.first == module_name.downcase
    }.compact

    begin
      links = module_class.run(to_download, already_downloaded, max).flatten.compact
    rescue StandardError => e
      puts e.to_s
      puts e.backtrace.first
      throw :reason, "There was a problem running the module #{module_name}."
    end
    
    # Update the module's cache
    begin
      if links.empty? && module_class.respond_to?("update_cache")
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
      puts e.to_s
      puts e.backtrace.first
      throw :reason, "Module #{module_name} had a problem updating its cache."
    end


    Lade.start_downloads(module_name.downcase, links)
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
        puts "Couldn't load host script #{name}"
        puts e.to_s
      end 
    }
  end
  
  def self.start_downloads(module_name, links)
    jd = nil
    
    links.each {
      |hash|
      
      # types: 0 = directlink, 10 = for jdownloader
      if (hash[:type] == 0)
        max = hash[:links].count
        for i in 0..max
          self.start_download(hash[:links][i], hash[:filenames][i])
        end
      elsif (hash[:type] == 10)
        jd = JDownloader.new(@@jdremote) if jd.nil?
        jd.process(hash[:links], @@downloads_folder_path)
      end
    
      ListFile.add_and_save(@@already_downloaded_list_path, module_name+":"+hash[:reference])
    }
  end
  
  def self.start_download(directlink, filename)
    # constructing the command; organized for clarity
    
    primary_cmd = "wget '#{directlink}'"
    con_params = "--continue --no-proxy --timeout 30"
    output_file = "--output-document='#{@@downloads_folder_path}#{filename}'"
    output_log = "--output-file='#{@@log_folder_path}#{filename}.txt'"
    
    wget = [primary_cmd, con_params, output_file, output_log].join(" ")
    
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
          puts e.to_s
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
      name, time = item.split(":")
      
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
          Lade.notify_smartphone(filename)
        end
      end
      
      torrent_configured = !@@torrent_autoadd_dir.empty? && File.directory?(@@torrent_autoadd_dir)
      torrent_downloads_move = (torrent_configured && !@@torrent_downloads_dir.empty? && File.directory?(@@torrent_downloads_dir))
      
      if (!(@@extract || torrent_configured))
        puts "Nothing to do."
        break
      end
      
      if (torrent_downloads_move)
        ListFile.new(@@torrent_history_path).list.each {
          |line|
          name, timestamp = line.split(":", 2)
          
          name = name.gsub(".torrent", "")
          
          if (File.exist?(@@torrent_downloads_dir+name))
            begin
              File.rename(@@torrent_downloads_dir+name, @@downloads_folder_path+name)
              puts "'#{@@torrent_downloads_dir+name}' moved to '#{@@downloads_folder_path}'"
            rescue StandardError => e
              puts e.backtrace.first
              puts e.to_s
              puts "Couldn't move '#{@@torrent_downloads_dir+name}' to '#{@@downloads_folder_path}'"
            end
          end
        }
      end
      
      archives = [] # .rar/.zip files needing extraction
      torrents = [] # .torrent files needing moving
      
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
      
      if (torrent_configured)
        moved = []
        @@torrent_autoadd_dir += "/" unless @@torrent_autoadd_dir.end_with?"/"
        torrents.each {
          |torrent|
          
          begin
            File.rename(@@downloads_folder_path+torrent, @@torrent_autoadd_dir+torrent)
            moved << "#{torrent}:#{Time.now.to_i}"
            puts "'#{torrent}' moved to '#{@@torrent_autoadd_dir}'"
          rescue StandardError => e
            puts "Couldn't move #{torrent}"
            puts e.to_s
          end
        }
        
        ListFile.add_and_save(@@torrent_history_path, moved)
      end
      
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
            
            Lade.notify_smartphone(no_extension)
            
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
              
              if ((extensions_to_keep.include?extension) || (File.new("#{extraction_folder}/#{file}").size >= (1024*128)) || is_directory)
                
                File.rename(
                "#{extraction_folder}/#{file}",
                "#{@@downloads_folder_path}#{file}")
                puts "'#{file}' moved to 'Downloads'"
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
              puts "Couldn't delete temporary extraction folder #{extraction_folder}."
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
      puts "Couldn't continue"
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