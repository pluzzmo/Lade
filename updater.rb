require 'rubygems'
require 'open-uri'

class Updater
	@@path = File.join(File.dirname(__FILE__), *%w[/])
	@@log_folder_path = @@path+"log/"
	
	def self.update
		interrupted = false
		restart_server = false
		
		begin
			current_rev = nil
			File.open(@@path+"rev", "r") { |f| current_rev = f.read.to_s.gsub(/\s/m, "") } if File.exist?(@@path+"rev")
			available_rev = nil
			begin
				available_rev = open("https://raw.github.com/inket/Lade/master/rev").read.to_s.gsub(/\s/m, "")
			rescue StandardError
				puts "Couldn't get rev file from repo."
			end

			if (current_rev != available_rev && !available_rev.nil? && !available_rev.empty?)
				puts "*Updating to commit #{available_rev} from #{current_rev || 'none'}."

				puts "Downloading zip..."
				system("wget", "--quiet", "https://codeload.github.com/inket/Lade/zip/#{available_rev}")
				throw StandardError.new unless $?.success?

				puts "Extracting..."
				system("unzip", "-qoC", "#{available_rev}", "-d", "#{@@path}")
				throw StandardError.new unless $?.success?

				puts "Moving..."
				`cp -a 'Lade-#{available_rev}/'* '#{@@path}'`
				throw StandardError.new unless $?.success?

				puts "Removing temporary files..."
				system("rm -rf Lade-#{available_rev}/")
				system("rm #{available_rev}")

				puts "Done."
				current_rev = available_rev
				File.open(@@path+"rev", "w") {|f| f.write(current_rev)}
				puts "*Updated to commit #{current_rev}!"

				restart_server = true
			else
				puts "Already up to date."
			end

			restart_server
		rescue StandardError => e
			puts e.backtrace.first
			puts "Error while checking for updates: #{e.to_s}"
		rescue Interrupt
			interrupted = true
		end

		raise Interrupt.new if interrupted # Silence the huge backtrace that may result if the user interrupts Lade's install
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
			modules_list = open("https://dl.dropbox.com/u/2439981/Lade/available_modules").read.to_s
			modules_list.lines {
				|line|
				file, description = line.split(":", 2)
				name = file.gsub(".rb", "").capitalize
				already_installed = File.exist?(@@path+"modules/"+file)
				available_modules << [name, description, file, already_installed]
			}
		rescue StandardError => e
			puts e.backtrace.first
			puts e.to_s
		end
		
		available_modules
	end

	def self.gen_available_modules_list
		list = []
		@@path = File.join(File.dirname(__FILE__), *%w[/])
		Dir.entries(@@path+"modules/").each {
			|entry|
			next if entry.start_with?(".")
			
			load @@path+"modules/"+entry
			module_class = eval(entry.gsub(".rb", "").capitalize)
			puts entry
			list << entry+":"+module_class.description
		}
		File.open(@@path+"available_modules", "w") do |f|
			f.write(list.join("\n"))
		end
	end
	
	def self.install_module(url_or_name)
		begin
			# we have to test with a single slash because we might get a bad url from Sinatra
			is_url = url_or_name.start_with?("http:/") || url_or_name.start_with?("https:/")
			url_or_name = url_or_name.gsub("https:/", "http:/").gsub("http://", "http:/").gsub("http:/", "http://") if is_url

			if (!is_url)
				current_rev = nil
				File.open(@@path+"rev", "r") { |f| current_rev = f.read.to_s.gsub(/\s/m, "") } if File.exist?(@@path+"rev")
				current_rev = "master" if current_rev.nil?
				
				url = "https://raw.github.com/inket/Lade/#{current_rev}/modules/#{url_or_name}"
			else
				url = url_or_name
			end

			file = url.split("/").last
			new_file = open(url).read.to_s
			File.open(@@path+"modules/"+file, "w") do
				|f|
				f.write(new_file)
			end
			
			true
		rescue StandardError => e
			puts e.backtrace.join("\n")
			puts "Couldn't install module from #{url_or_name}"
			
			false
		end
	end
	
	def self.log
		orig_stdout = $stdout
		$stdout = File.new("#{@@log_folder_path}#{Time.now.strftime("%Y%m%d-h%H")}.log", "a")
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

Updater.update if ARGV[0] == "--update" # Force update
Updater.gen_available_modules_list if ARGV[0] == "-g" # Server only