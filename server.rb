require "rubygems"
require "bundler/setup"

require 'sinatra'
require 'haml'
require 'rufus/scheduler'

# things you might want to change
@@debug = false
port = 3333
ip = "0.0.0.0"

# ---

# probably the most important def
path = File.join(File.dirname(__FILE__), *%w[/])
@@path = path

# redirect all output to a file
output_file = path+"output.log"
$stdout = File.new(output_file, "w")
$stderr = $stdout
$stdout.sync = true
$stderr.sync = true

# load Lade, some Sinatra methods might need it
load path+"lade.rb"
Lade.prep_directories

# get settings/preferences
settings = FileConfig.getConfig
@@settings = settings
freq = settings["freq"] ? "#{settings["freq"]}m" : '5m'
require_authentication = settings["authentication"].nil? ? false : settings["authentication"]
if (require_authentication)
	@@auth_name, @@auth_pw = ListFile.new(path+"config/password").list
	
	require_authentication = false if @@auth_name.nil? || @@auth_pw.nil?
end


# set up the timer
@@scheduler = Rufus::Scheduler.start_new
@@job = nil

def start_scheduler(frequency)
	@@job.unschedule if !@@job.nil?

	@@job = @@scheduler.every frequency, :first_at => Time.now, :mutex => 'script' do
		|the_job|

		settings = FileConfig.getConfig
		if (settings["enable_updates"].nil? || settings["enable_updates"])
			load @@path+"updater.rb"
			Updater.main
		end

		load @@path+"lade.rb"
		Lade.main
	end
end

start_scheduler(freq) if !@@debug

# configure Sinatra
configure do
	set :port => port
	set :ip => ip
end

def self.enable_authentication
	puts "Basic HTTP Authentication enabled. Username is: #{@@auth_name}."
	puts "If you can't connect, delete 'config/password' and restart the server."
	
	use Rack::Auth::Basic, "Protected Area" do |username, password|
		username == @@auth_name && password == @@auth_pw
	end
end
enable_authentication if require_authentication

# save PID
File.open(path+"config/pid", "w") do |f|
	f.write(Process.pid.to_s)
end

### Sintra request methods

get '/' do
	lines = `ps ax | grep wget`.split "\n"
	lines = lines.select{|line| line.strip.match(/wget$/).nil? }

	# Get list of downloaded files
	downloads_folder_path = path+"downloads/"
	@downloaded = (Dir.entries downloads_folder_path).collect {
		|entry|
		entry if ((!entry.start_with?".") && (!entry.end_with?".log"))
	}.compact

	currently_extracting = Dir.entries(downloads_folder_path).collect {
		|entry|
		entry if entry.end_with?"_extract.log"
	}.compact
	
	# See if Lade is extracting any files and report progress
	@extracting = currently_extracting.count > 0
	@extracting_progress = "0"
	currently_extracting.each {
		|extract_log|
		
		content = ""
		File.open(downloads_folder_path+extract_log, "r") do |f|
			content = f.read.to_s
		end
		
		progress = content.scan(/(\d+)\%/im).flatten.uniq.collect { |perc|
			perc.to_i
		}.sort.last
		
		@extracting_progress = progress.to_i
		break
	}
	@extracting_txt = "extracting"
	(@extracting_progress.to_i % 4).times {
		@extracting_txt += "."
	}
	
	# Read the errors log if previous extractions had any errors
	@unrar_errors = File.exist?(downloads_folder_path+"unrar-error.log")
	if (@unrar_errors)
		File.open(downloads_folder_path+"unrar-error.log", "r") do |f|
			@unrar_errors = f.read.gsub("\n", "<br>")
		end
	end

	# Get list of downloading files, progress, speed, eta, etc.
	@global_speed = 0
	@downloads = []
	lines.each {
		|line|
		match = line.scan(/--output-file=(.*?)$/)
		next if match.empty?

		pid = line.scan(/^\s*\d+/).first.to_s.strip

		begin
			log_file = match.flatten.first
			log_file_lines = (File.open log_file, "r").read.split("\n")

			if log_file_lines.last.match(/\s\d+\%/)
				last_line = log_file_lines.last
			else
				last_line = log_file_lines[log_file_lines.count-2]
			end

			matches = last_line.match(/\s\d+\%.*$/).to_s.split(" ")
			file = log_file.split("/").last.gsub(/.txt$/, "")

			@downloaded.delete(file)
			@global_speed = @global_speed + Helper.to_bytes(matches[1])
			@downloads << {:file => file, :progress => matches[0], :speed => matches[1], :eta => matches[2], :pid => pid}
		rescue
			next
		end
	}

	@global_speed = Helper.human_size(@global_speed, 8)+"/s"

	# Add some useful information to the downloaded files list
	@downloaded = @downloaded.collect {
		|item|
		ctime = File.ctime(downloads_folder_path+item)
		htime = Helper.human_time(ctime)
		size = Helper.human_size(File.size(downloads_folder_path+item), 10)

		{:file => item, :ctime => ctime, :htime => htime, :link => item, :size => size}
	}.sort {
		|x,y|
		y[:ctime] <=> x[:ctime]
	}

	more = @downloaded.count - 10
	if @downloaded.count > 10
		@downloaded = @downloaded[0..10]
		@downloaded << { :file => "and #{more} more...", :ctime => "", :htime => "", :link => "", :size => "", :class => "andmore"}
	end
	
	# Get list of torrents started in the last 24 hours
	torrent_history_path = path+"config/torrent_history"
	@torrent_history = ListFile.new(torrent_history_path).list
	@torrent_history.sort! {
		|x, y| # sort by timestamp
		a, b = x.split(":", 2)
		c, d = y.split(":", 2)
		d.to_i <=> b.to_i
	}
	@torrent_history = @torrent_history.collect {
		|item|
		torrent, time, ignore = item.split(":", 3)
		
		[torrent, Helper.relative_time(time)] if ignore.to_i == 0
	}.compact
	
	if @torrent_history.count > 5
		more = ["and "+(@torrent_history.count-5).to_s+" more...", ""]
		@torrent_history = @torrent_history.take(5)
		@torrent_history << more
	end
	
	# Get list of installed modules
	@installed_modules = Lade.available_modules
	
	# Get list of broken modules
	@broken_modules = @installed_modules.empty? ? [] : ListFile.new(path+"config/"+"broken_modules").list
	
	# Get Lade status
	@config = FileConfig.getConfig
	@config["enabled"] = !@config["stopped"]

	# Some formatting
	global_speed_str = " @ "+@global_speed

	@page_title = "Lade"
	@header = @downloads.count.to_s+" download"+(@downloads.count==1 ? "" : "s" )
	if (@downloads.count > 0)
		@page_title = @header+global_speed_str
		@header = @page_title
	end

	haml :index, :layout => request.xhr? ? false : :index_layout
end

get '/toggle' do
	FileConfig.setValue("stopped", !FileConfig.getConfig["stopped"])
	redirect to("/")
end

get '/settings' do
	settings = FileConfig.getConfig
	@freq = settings["freq"] || 5
	@extract = settings["extract"].nil? ? true : settings["extract"]
	@updates = settings["enable_updates"].nil? ? true : settings["enable_updates"]
	@max_concurrent_downloads = settings["max_concurrent_downloads"] || 0
	@torrent_autoadd_dir = settings["torrent_autoadd_dir"] || ""
	@torrent_downloads_dir = settings["torrent_downloads_dir"] || ""
	@authentication = settings["authentication"] || false
	@auth_login, @auth_password = ListFile.new(path+"config/password").list
	@modules = Lade.available_modules

	haml :settings
end

post '/settings' do
	begin
		settings = FileConfig.getConfig
		settings["freq"] = params[:freq].to_i >= 3 ? params[:freq].to_i : 5
		start_scheduler("#{settings["freq"]}m")
		settings["max_concurrent_downloads"] = params[:max_concurrent_downloads].to_i
		settings["extract"] = (params[:extract] == "true" ? true : false)
		settings["enable_updates"] = (params[:updates] == "true" ? true : false)
		settings["torrent_autoadd_dir"] = params[:torrent_autoadd_dir]
		settings["torrent_downloads_dir"] = params[:torrent_downloads_dir]
		settings["authentication"] = (params[:authentication] == "true" ? true : false)
		
		if (!params[:auth_password].nil? && !params[:auth_password].empty? && params[:auth_password] != "********" && !params[:auth_login].nil? && !params[:auth_login].empty?)
			ListFile.overwrite(path+"config/password", [params[:auth_login], params[:auth_password]])
		end
		
		FileConfig.saveConfig(settings)

		redirect to("/")
	rescue
		haml :settings
	end
end


get '/module/:module' do
	cond1 = (!params[:module].nil? && !params[:module].empty?)
	cond2 = (Lade.available_modules.include?(params[:module].capitalize))

	if (cond1 && cond2)
		@module = params[:module].capitalize

		load path+"modules/"+params[:module].downcase+".rb"
		module_class = eval("#{@module}")

		if module_class.respond_to?("settings_notice")
			@notice = module_class.settings_notice.gsub("\n", "<br>")
		end

		@list = ListFile.new(path+"config/"+params[:module].downcase).list.join("\n")
		haml :module_settings
	else
		redirect to("/")
	end
end

post '/module/:module' do
	cond1 = (!params[:module].nil? && !params[:module].empty?)
	cond2 = (Lade.available_modules.include?(params[:module].capitalize))
	cond3 = !params[:list].nil?

	if (cond1 && cond2 && cond3)
		list = params[:list].split("\n").collect {
			|item|
			item.strip
		}.compact

		listfile = ListFile.new(path+"config/"+params[:module].downcase)
		listfile.list = list
		listfile.save

		@success = true
		@module = params[:module].capitalize

		load path+"modules/"+params[:module].downcase+".rb"
		module_class = eval("#{@module}")

		if module_class.respond_to?("settings_notice")
			@notice = module_class.settings_notice.gsub("\n", "<br>")
		end

		@list = ListFile.new(path+"config/"+params[:module].downcase).list.join("\n")

		haml :module_settings
	else
		redirect to("/")
	end
end

get '/ondemand' do
	@modules = Lade.available_modules
	@modules = @modules.collect {
		|module_name|
		load path+"modules/"+module_name.downcase+".rb"
		module_class = eval("#{module_name}")
		
		next unless module_class.respond_to?("has_on_demand?")
		[module_name, module_class.has_on_demand?]
	}
	haml :ondemand
end

get '/ondemand/:module' do
	cond1 = (!params[:module].nil? && !params[:module].empty?)
	cond2 = (Lade.available_modules.include?(params[:module].capitalize))

	if (cond1 && cond2)
		@module = params[:module].capitalize

		load path+"modules/"+params[:module].downcase+".rb"
		module_class = eval("#{@module}")

		if module_class.respond_to?("download_on_demand") && module_class.respond_to?("on_demand")
			@list = module_class.on_demand
		end

		haml :module_ondemand
	else
		redirect to("/")
	end
end

get '/ondemand/:module/*' do
	redirect to("/ondemand/#{params[:module]}") if params[:splat].first.empty?

	# stream(:keep_open) { |out| connections << out }
	
	cond1 = (!params[:module].nil? && !params[:module].empty?)
	cond2 = (Lade.available_modules.include?(params[:module].capitalize))

	if (cond1 && cond2)
		@module = params[:module].capitalize
		@reference = params[:splat].first.split("/")

		if @reference.count == 1
			@reference = @reference.first 
		else
			step = @reference.count
		end

		load path+"modules/"+params[:module].downcase+".rb"
		module_class = eval("#{@module}")

		begin
			method_name = "download_on_demand"+(step ? "_step#{step.to_s}" : "")

			if module_class.respond_to?(method_name) && module_class.respond_to?("on_demand")
				@result = eval("module_class.#{method_name}(@reference)")
			end

			raise StandardError.new("Module didn't return further download information for #{@reference.to_s}") unless @result && !@result.empty?

			if @result.first.kind_of?(Hash) # module returned links
				Lade.start_downloads(@module.downcase, @result)
				@success = true
			else # module returned another list
				@list = @result
			end
		rescue StandardError => e
			puts e.to_s
			puts e.backtrace.join("\n")
		end

		haml :module_ondemand
	else
		redirect to("/")
	end
end

get '/removeall' do
	`killall wget`
	redirect to("/")
end

get '/remove/:download_pid' do
	`kill #{params[:download_pid]}`
	redirect to("/")
end

get '/delete_log' do
	begin
		File.delete(File.join(File.dirname(__FILE__), *%w[downloads/unrar-error.log]))
	rescue StandardError => e
		puts e.backtrace.first
		puts e.to_s
	end
	redirect to("/")
end

get '/delete_log_and_files' do
	begin
		File.delete(File.join(File.dirname(__FILE__), *%w[downloads/unrar-error.log]))

		downloads_folder = path+"downloads/"
		
		Dir.entries(downloads_folder).each {
			|file|
			
			next if !File.exist?(downloads_folder+file)
			
			# Delete empty directories
			if (File.directory?(downloads_folder+file))
				Dir.delete(downloads_folder+file) if Dir.entries(downloads_folder+file).select {
					|entry|
					(entry != ".") && (entry != "..")
				}.empty?
			end
			
			# Delete archives that failed extraction
			if (file =~ /\.(zip|rar)\_failed$/i)
				File.delete(downloads_folder+file)
				is_multipart = (file =~ /\.part\d+\.rar\_failed$/i)

				# Delete the other parts if it's a multipart archive
				if (is_multipart)
					no_extension = file.gsub(/part\d+\.rar\_failed$/i, "")
					
					Dir.entries(downloads_folder).each {
						|entry|
						
						is_dir = File.directory?(downloads_folder+entry)

						if entry.start_with?(no_extension) && !is_dir
							File.delete(downloads_folder+entry)
						end
					}
				end
			end
		}
	rescue StandardError => e
		puts e.backtrace.first
		puts e.to_s
	end
	redirect to("/")
end

get '/clear_torrent_history' do
	begin
		th_path = path+"config/torrent_history"
		lf = ListFile.new(th_path)
		lf.list = lf.list.collect {
			|line|
			torrent, time, ignore = line.split(":", 3)
			"#{torrent}:#{time}:1"
		}
		lf.save
	rescue StandardError => e
		puts e.backtrace.first
		puts e.to_s
	end
	redirect to("/")
end

get '/install' do
	load path+"updater.rb"
	@modules = Updater.available_modules
	
	haml :module_install
end

get '/install/*' do
	url_or_name = params[:splat].join("")
	if (url_or_name.nil? || url_or_name.empty?)
		redirect to("/install")
	end
	
	load path+"updater.rb"
	@result = Updater.install_module(url_or_name)
	@modules = Updater.available_modules
	
	haml :module_install
end

get '/api/downloads/count' do
	lines = `ps ax | grep wget`.split "\n"
	lines = lines.select{|line| line.strip.match(/wget$/).nil? && !line.strip.include?("(wget")}
	
	lines.count.to_s
end

get '/restart' do
	@@scheduler.in '2s' do
		load @@path+"updater.rb"
		Updater.restart
	end
	
	redirect to("/restart.html")
end

get '/quit' do
	@@scheduler.in '2s' do
		load @@path+"updater.rb"
		Updater.quit
	end
	
	redirect to("/quit.html")
end