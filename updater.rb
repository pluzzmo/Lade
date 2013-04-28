require 'rubygems'
require 'open-uri'

class Updater
	@@server = "https://dl.dropbox.com/u/2439981/Lade/"
	@@path = File.join(File.dirname(__FILE__), *%w[/])
	@@log_folder_path = @@path+"log/"
	
	def self.update(force = false)
		begin
			restart_server = false
			
			server_rev = open(@@server+"version").read.to_s
			server_files = {}
			server_rev.lines {
				|line|
				a, b = line.split(":")
				server_files[a] = b.to_i
			}
			
			server_files.each {
				|path, server_mtime|
				
				dir = path.split("/")
				file = dir.pop
				dir = dir.join("/")+"/"
				
				local_mtime = nil
				begin
					local_mtime = File.mtime(@@path+dir+file).to_i
				rescue
				end
				local_mtime = local_mtime.to_i
				
				# Compare modification date, replace old files with new ones
				if ((server_mtime > local_mtime || force) && (dir != "modules/" || local_mtime != 0))
					begin
						# build directory tree if inexistent
						if !File.exist?(@@path+dir)
							dir_tree = dir.split("/")
							
							dir_tree.count.times { |i|
								if !File.exist?(@@path+dir_tree.take(i+1).join("/"))
									Dir.mkdir(@@path+dir_tree.take(i+1).join("/"))
								end
							}
						end
						
						# get new file, replace old one
						new_file = open(@@server+dir+file).read.to_s
						File.delete(@@path+dir+file) if File.exist?(@@path+dir+file)
						File.open(@@path+dir+file, "w") do
							|f|
							f.write(new_file)
						end
						
						restart_server = true if file == "server.rb"
						puts "File '#{dir+file}' updated."
					rescue StandardError => e
						puts "Couldn't update file '#{dir+file}': #{e.to_s}"
					end
				end
				
				# remove deprecated files
				if (server_mtime == -1 && File.exist?(@@path+dir+file))
					begin
						File.delete(@@path+dir+file)
						puts "File '#{dir+file}' removed."
					rescue StandardError => e
						puts e.backtrace.first
						puts e.to_s
					end
				end
			}
						
			restart_server
		rescue StandardError => e
			puts e.backtrace.first
			puts "Error while checking for updates: #{e.to_s}"
		end
	end
	
	def self.update_broken_modules_list
		modules_folder = @@path+"modules/"
		broken_modules = []
		
		Dir.entries(modules_folder).each {
			|entry|
			
			next if entry.start_with?"."
			
			module_path = modules_folder+entry
			entry = entry.capitalize
			entry = ((entry.end_with?".rb") ? entry.gsub(".rb", "") : entry)
			broken = false
			
			begin
				load module_path
				broken = eval("#{entry}.broken?")
			rescue StandardError => e
				broken = true
			end
			
			broken_modules << entry if broken
		}
		
		broken_modules_list_path = @@path+"config/broken_modules"
		ListFile.overwrite(broken_modules_list_path, broken_modules)
	end
	
	def self.available_modules
		available_modules = []
		begin
			server_rev = open(@@server+"version").read.to_s
			server_rev.lines {
				|line|
				a, b, c = line.split(":", 3)
				dir, file = a.split("/")
				
				if dir == "modules"
					name = file.gsub(".rb", "").capitalize
					already_installed = File.exist?(@@path+dir+"/"+file)
					available_modules << [name, c || "", file, already_installed]
				end
			}
		rescue StandardError => e
			puts e.backtrace.first
			puts e.to_s
		end
		
		available_modules
	end
	
	def self.install_module(url_or_name)
		begin
			is_url = url_or_name.start_with?("http:/") || url_or_name.start_with?("https:/")
			url_or_name = url_or_name.gsub("https:/", "http:/").gsub("http://", "http:/").gsub("http:/", "http://") if is_url
			dir = "modules/"
			url = (is_url ? url_or_name : @@server+dir+url_or_name)
			file = url.split("/").last
			
			new_file = open(url).read.to_s
			File.open(@@path+dir+file, "w") do
				|f|
				f.write(new_file)
			end
			
			true
		rescue StandardError => e
			puts e.backtrace.first
			puts "Couldn't install module from #{url_or_name}"
			
			false
		end
	end
	
	def self.gen_version_file
		lines = gen_for_dir("")
		
		File.open(@@path+"version", "w") do
			|f|
			f.write(lines.join("\n"))
		end
	end
	
	def self.gen_for_dir(dir)
		dir = dir+"/" unless dir.empty? || dir.end_with?("/")
		return [] if ["downloads/", "log/", "config/", "cache/"].include?dir
		
		lines = []
		
		Dir.entries(@@path+dir).each {
			|entry|
			next if ((entry.start_with?(".")) || (entry == "version") || (entry == "install.rb") || entry.end_with?(".log"))
			
			if (File.directory?(@@path+dir+entry))
				lines = lines + gen_for_dir(dir+entry)
				next
			end
			
			local_mtime = File.mtime(@@path+dir+entry).to_i.to_s
			
			if (dir == "modules/")
				description = ""
				
				begin
					load @@path+dir+entry
					class_name = entry.capitalize.gsub(".rb", "")
					module_class = eval("#{class_name}")
					description = module_class.description.gsub("\n", " ")
				rescue StandardError => e
					puts e.to_s
					puts e.backtrace.first
				end
				
				lines << "#{dir+entry}:#{local_mtime}:#{description}"
			else
				lines << "#{dir+entry}:#{local_mtime}"
			end
		}
		
		lines
	end
	
	def self.log
		orig_stdout = $stdout
		$stdout = File.new("#{@@log_folder_path}#{Time.now.strftime("%Y%m%d-h%H")}.txt", "a")
		$stdout.sync = true
		puts "@ #{Time.now.to_s} - Checking for updates...\n"
		yield
	ensure
		puts "\n"
		$stdout = orig_stdout
		$stdout.sync = true
	end
	
	def self.gem_available?(name)
		Gem::Specification.find_by_name(name)
	rescue Gem::LoadError
		false
	rescue
		Gem.available?(name)
	end
	
	def self.install_missing_gems
		needed_gems = ["thin", "sinatra", "haml", "rufus-scheduler", "json", "ruby_gntp"]
		
		missing_gems = []
		needed_gems.each {
			|name|
			missing_gems << name unless Updater.gem_available?(name)
		}
		
		if (!missing_gems.empty?)
			puts "Missing gems: #{missing_gems.join(', ')}."
			puts "Installing..."
			Dir.chdir(@@path)
			system("bundle", "install")
		end
	end
	
	def self.get_pid
		pid = (ARGV[0] == "stop" ? nil : Process.pid.to_s)
		if (File.exist?(@@path+"config/pid"))
			File.open(@@path+"config/pid", "r") do |f|
				r = f.read.to_s
				pid = r unless (r.nil? || r.empty?)
			end
		else
			r = `pgrep -f 'ruby #{@@path}server.rb'`
			pid = r.split("\n")[1] unless (r.nil? || r.empty? || r.lines.count < 2)
		end

		pid
	end
	
	def self.restart
		puts "Restarting server..."
		pid = Updater.get_pid
		if (pid.nil?)
			Updater.start
		else
			File.delete(@@path+"config/pid") if File.exist?(@@path+"config/pid")
			IO.popen("kill #{pid} && sleep 3 && ruby #{@@path}server.rb&")
			puts "Lade restarted."
		end
	end
	
	def self.start
		if (File.exist?(@@path+"config/pid"))
			puts "Lade seems to be already running. Remove the pid file if you're certain that Lade isn't running."
		else
			IO.popen("ruby #{@@path}server.rb&")
			puts "Lade started."
		end
	end
	
	def self.forcestart
		IO.popen("ruby #{@@path}server.rb&")
		puts "Lade started."
	end
	
	def self.quit
		puts "Stopping server..."
		pid = Updater.get_pid
		
		if (!pid.nil?)
			File.delete(@@path+"config/pid") if File.exist?(@@path+"config/pid")
			`kill #{pid}`
			puts "Lade stopped."
		else
			puts "Lade doesn't seem to be running."
		end
	end

	def self.main
		Updater.log do
			Updater.restart if Updater.update
		end
	end
end

Updater.update(true) if ARGV[0] == "-f" # Force update
Updater.update if ARGV[0] == "--test" # Test updating
Updater.gen_version_file if ARGV[0] == "-g" # Generate version file (repo only)