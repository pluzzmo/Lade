require "rubygems"

require 'sinatra'
require 'haml'
require 'rufus/scheduler'
require 'json'

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

@@lade_checking_for_new_downloads = false

# set up the timer
@@scheduler = Rufus::Scheduler.start_new
@@job = nil

def start_scheduler(frequency)
	@@job.unschedule if !@@job.nil?

	@@job = @@scheduler.every frequency, :first_at => Time.now, :mutex => 'script' do
		|the_job|
		
		@@lade_checking_for_new_downloads = true
		settings = FileConfig.getConfig
		if (settings["enable_updates"].nil? || settings["enable_updates"])
			load @@path+"updater.rb"
			Updater.main
		end

		load @@path+"lade.rb"
		Lade.main
		@@lade_checking_for_new_downloads = false
	end
end

start_scheduler(freq) if !@@debug

# configure Sinatra
configure do
	set :port => port
	set :bind => ip
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
		
	# Read the errors log if previous extractions had any errors
	@unrar_errors = File.exist?(downloads_folder_path+"unrar-error.log")
	if (@unrar_errors)
		File.open(downloads_folder_path+"unrar-error.log", "r") do |f|
			@unrar_errors = f.read.gsub("\n", "<br>")
		end
	end
	
	begin
		@queue = YAMLFile.new(@@path+"config/queue").value || []
	rescue Exception
		@queue = []
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
			file = log_file.split("/").last.gsub(/.log$/, "")

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
	@broken_modules = @installed_modules.empty? ? [] : ListFile.new(path+"config/broken_modules").list
	
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
	
	@checking = @@lade_checking_for_new_downloads

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
	@require_confirm = settings["require_confirm"].nil? ? false : settings["require_confirm"]
	@max_concurrent_downloads = settings["max_concurrent_downloads"] || 0
	@torrent_autoadd_dir = settings["torrent_autoadd_dir"] || ""
	@torrent_downloads_dir = settings["torrent_downloads_dir"] || ""
	@authentication = settings["authentication"] || false
	@auth_login, @auth_password = ListFile.new(path+"config/password").list
	@growl_notifications = settings["growl_notifications"] || false
	@growl_host = settings["growl_host"] || ""
	@growl_port = settings["growl_port"] || ""
	@growl_password = settings["growl_password"] || ""
	@notify_on_download_start = settings["notify_on_download_start"].nil? ? false : settings["notify_on_download_start"]
	@notify_on_download_finish = settings["notify_on_download_finish"].nil? ? false : settings["notify_on_download_finish"]
	@notify_on_download_confirm = settings["notify_on_download_confirm"].nil? ? false : settings["notify_on_download_confirm"]
	
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
		settings["require_confirm"] = (params[:require_confirm] == "true" ? true : false)
		settings["torrent_autoadd_dir"] = params[:torrent_autoadd_dir]
		settings["torrent_downloads_dir"] = params[:torrent_downloads_dir]
		settings["authentication"] = (params[:authentication] == "true" ? true : false)
		
		if (!params[:auth_password].nil? && !params[:auth_password].empty? && params[:auth_password] != "********" && !params[:auth_login].nil? && !params[:auth_login].empty?)
			ListFile.overwrite(path+"config/password", [params[:auth_login], params[:auth_password]])
		end
		
		settings["growl_notifications"] = (params[:growl_notifications] == "true" ? true : false)
		settings["growl_host"] = params[:growl_host]
		settings["growl_port"] = params[:growl_port]
		settings["growl_password"] = params[:growl_password]
		settings["notify_on_download_start"] = (params[:notify_on_download_start] == "true" ? true : false)
		settings["notify_on_download_finish"] = (params[:notify_on_download_finish] == "true" ? true : false)
		settings["notify_on_download_confirm"] = (params[:notify_on_download_confirm] == "true" ? true : false)
		
		FileConfig.saveConfig(settings)
		Lade.load_config
		
		redirect to("/")
	rescue
		haml :settings
	end
end

post '/listsource/:source' do
	wanted_source = params[:source]
	
	if (!wanted_source.nil? && !wanted_source.empty?)
		login = params[:login]
		password = params[:password]
		
		ListSource.get(wanted_source, login, password)
	end
end

get '/module/:module' do
	valid_module_name = (!params[:module].nil? && !params[:module].empty?)
	module_exists = (Lade.available_modules.include?(params[:module].capitalize))

	if (valid_module_name && module_exists)
		@module = params[:module].capitalize

		load path+"modules/"+params[:module].downcase+".rb"
		module_class = eval("#{@module}")

		if module_class.respond_to?("settings_notice")
			@notice = module_class.settings_notice.gsub("\n", "<br>")
		end
		
		@source = nil
		if module_class.respond_to?("list_sources")
			@sources = module_class.list_sources.collect {
				|source|
				if (source.kind_of?(Array))
					@source = source
					nil
				else
					source
				end
			}.compact.uniq
		end
		@sources_info = ListSource.info

		@list = ListFile.new(path+"config/"+params[:module].downcase).list.join("\n")
		haml :module_settings
	else
		redirect to("/")
	end
end

post '/module/:module' do
	valid_module_name = (!params[:module].nil? && !params[:module].empty?)
	module_exists = (Lade.available_modules.include?(params[:module].capitalize))
	valid_list = !params[:list].nil?

	if (valid_module_name && module_exists && valid_list)
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
		
		@source = nil
		if module_class.respond_to?("list_sources")
			@sources = module_class.list_sources.collect {
				|source|
				if (source.kind_of?(Array))
					@source = source
					nil
				else
					source
				end
			}.compact.uniq
		end
		@sources_info = ListSource.info

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

get '/ondemand/*' do
	redirect to("/ondemand") if params[:splat].empty? || params[:splat].first.empty?
	parts = params[:splat].first.split("/")
	
	module_name = parts.shift
	reference = parts.join("/")

	valid_module_name = !module_name.empty?
	module_exists = (Lade.available_modules.include?(module_name.capitalize))

	if (valid_module_name && module_exists)
		@module = module_name.capitalize
		@reference = reference
		@stream_uri = "/stream/ondemand/#{@module}/#{@reference}"
		
		haml :module_ondemand
	else
		redirect to("/")
	end
end

def presentable_link_groups(link_groups, reset_temp_file = false)
	# add the links to a temp file so we can start them if needed without
	# doing all of this again
	yaml_file = YAMLFile.new(@@path+"config/temp")
	yaml_file.overwrite([]) if reset_temp_file
	yaml_file << link_groups
	
	# present the links to the user as a legible list
	list = []
	link_groups.each {
		|group|
		
		valid_group = false
		begin
			valid_group = true if (!group[:files].first.nil?)
		rescue
		end
		
		next if !valid_group
		
		group_name = group[:name] || group[:reference]
		group_host = group[:host] ? "[#{group[:host]}] " : ""
		group_size = group[:size] ? " (#{Helper.human_size(group[:size])})" : ""
		
		friendly_name = "#{group_host}#{group_name}#{group_size}"
		start_from_temp_uri = "/temp/start/#{group_name}#{':'+group[:host] if group[:host]}"
		
		list << [friendly_name, start_from_temp_uri]
	}
	
	list
end

get '/stream/ondemand/*' do
	content_type "text/event-stream"
	headers "Access-Control-Allow-Origin" => "*" # IE8 fix
	stream do |out|
		# < Windows Phone + Android: EventSource fix (4KB padding)
		out << ":"+(" "*4096)+"\n"
		out << "retry: 2000\n"
		# />

		if (!params[:splat].empty? && !params[:splat].first.empty?)
			parts = params[:splat].first.split("/")
			
			module_name = parts.shift
			reference = parts.join("/")
			reference = nil if reference.empty?
			
			valid_module_name = !module_name.empty?
			module_exists = (Lade.available_modules.include?(module_name.capitalize))
			
			if (valid_module_name && module_exists)
				load path+"modules/"+module_name.downcase+".rb"
				@module = module_name.capitalize
				module_class = eval("#{@module}")
				
				if module_class.respond_to?("on_demand")
					out << "data: #{{:title => 'Loading...', :progress => '0%'}.to_json}\n\n"
					
					begin
						threads = module_class.on_demand(reference)
						reset_temp_file = true
						
						if (!threads.empty? && threads.first.kind_of?(Thread))
							# Module sent us threads so we'll send new data to browser everytime a thread finishes
							start = Time.now
							thread_count = threads.count
						
							until (threads.empty? || (Time.now - start > 60)) do
								threads.each {
									|thread|
									progress = (((thread_count - (threads.count-1))/thread_count.to_f)*100).to_i
									
									if (thread["list"]) # Module returned another choice for the user
										out << "data: #{{:data => thread["list"], :progress => progress.to_s+'%'}.to_json}\n\n"
										threads.delete(thread)
									elsif (thread["groups"]) # Module returned links
										link_groups = thread["groups"]
										link_groups.each {
											|group|
											group[:module] = @module
										}
										list = presentable_link_groups(link_groups, reset_temp_file)
										reset_temp_file = false
										out << "data: #{{:data => list, :progress => progress.to_s+'%'}.to_json}\n\n"
										
										threads.delete(thread)
									end
								}
								
								sleep 1 unless threads.empty?
							end
						
							# kill remaining threads if execution time > 60s
							threads.each {
								|thread|
								thread.kill
							}
						else
							# Module sent us data so we'll just transfer it directly
							data = threads
							progress = 100
							if (!data.empty? && data.first.kind_of?(Hash)) # module returned links
								data.each {
									|group|
									group[:module] = @module
								}
								list = presentable_link_groups(data)
								out << "data: #{{:data => list, :progress => progress.to_s+'%'}.to_json}\n\n"
							else # module returned another choice for the user
								out << "data: #{{:data => data, :progress => progress.to_s+'%'}.to_json}\n\n"
							end
						end
					rescue StandardError => e
						message = "Module #{@module} had an error. Refer to the logs for details."
						puts PrettyError.new(message, e, true)
						out << "data: #{{:error => message}.to_json}\n\n"
					end
				else
					out << "data: #{{:error => 'Module doesn\'t support On Demand'}.to_json}\n\n"
				end
			end
		end
		out << "data: #{{:close => true}.to_json}\n\n"
	end
end

get '/temp/start/*' do
	redirect to("/") if params[:splat].empty? || params[:splat].first.empty?
	
	@stream_uri = "/stream/temp/start/"+params[:splat].join("")
	haml :module_ondemand
end

get '/stream/temp/start/*' do
	content_type "text/event-stream"
	headers "Access-Control-Allow-Origin" => "*" # IE8 fix
	stream do |out|
		# < Windows Phone + Android: EventSource fix (4KB padding)
		out << ":"+(" "*4096)+"\n"
		out << "retry: 2000\n"
		# />
		
		out << "data: #{{:title => 'Starting downloads...'}.to_json}\n\n"
		
		if (!params[:splat].empty?)
			reference = params[:splat].first

			# get the host and correct reference if the format is <ref>:<host>
			host = reference.reverse.split(":", 2).first.reverse
			if (host != reference)
				reference = reference.reverse.split(":", 2).last.reverse
			else
				host = nil
			end
			
			array = YAMLFile.new(@@path+"config/temp").value
			
			wanted_group = nil
			first_pass = true
			Helper.attempt(2) {
				array.each {
					|group|
					name_matches = (!group[:name].nil? && group[:name] == reference)
					ref_matches = (!group[:reference].nil? && group[:reference] == reference)
					
					host_ok = (host.nil? || group[:host] == host)
					
					if (((name_matches && first_pass) || (ref_matches && !first_pass)) && host_ok)
						wanted_group = group
						break
					end
				}
				
				first_pass = false
				raise StandardError.new("Didn't find the requested downloads.") if wanted_group.nil?
			}
			
			if (wanted_group)
				begin
					Lade.start_downloads(wanted_group[:module], [wanted_group], true)
					out << "data: #{{:message => 'Downloads started successfully.'}.to_json}\n\n"
				rescue StandardError => e
					message = "Lade couldn't start the downloads."
					puts PrettyError.new(message, e, true)
					out << "data: #{{:error => message}.to_json}\n\n"
				end
			else
				out << "data: #{{:error => 'Unexpected error occured.'}.to_json}\n\n"
			end
		end
		
		out << "data: #{{:close => true}.to_json}\n\n"
	end
end

get %r{/history/?$} do
	file = YAMLFile.new(@@path+"config/download_history")
	@items = file.value.reverse
	
	haml :history
end

get '/history/start/:ref' do
	file = YAMLFile.new(@@path+"config/download_history")
	history = file.value
	reference = params[:ref]
	to_start = nil
	if (history)
		history.each {
			|hash|
			to_start = hash if (hash[:reference] == reference)
		}
		
		if (to_start)
			Lade.start_downloads(to_start[:module], [to_start], true)
		end
	end
	
	redirect to("/")
end

get '/queue/start/:ref' do
	file = YAMLFile.new(@@path+"config/queue")
	queue = file.value
	reference = params[:ref]
	to_start = nil
	if (queue)
		queue = queue.delete_if {
			|hash|
			if (hash[:reference] == reference)
				to_start = hash
				true
			else
				false
			end
		}
		
		if (to_start)
			Lade.start_downloads(to_start[:module], [to_start], true)
			file.overwrite(queue)
		end
	end
	
	redirect to("/")
end

get '/queue/remove/:ref' do
	file = YAMLFile.new(@@path+"config/queue")
	queue = file.value
	reference = params[:ref]

	if (queue)
		queue = queue.delete_if {
			|hash|
			hash[:reference] == reference
		}
		file.overwrite(queue)
	end
	
	redirect to("/")
end

get '/queue/clear' do
	YAMLFile.new(@@path+"config/queue").overwrite([])
	
	redirect to("/")
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

get '/api/waiting/count' do
	(YAMLFile.new(@@path+"config/queue").value || []).count.to_s
end

get '/restart' do
	@@scheduler.in '2s' do
		load @@path+"updater.rb"
		Updater.restart
	end
	
	redirect to("/restart.html")
end

get '/stop' do
	@@scheduler.in '2s' do
		load @@path+"updater.rb"
		Updater.quit
	end
	
	redirect to("/quit.html")
end

get '/quit' do
	redirect to("/stop")
end