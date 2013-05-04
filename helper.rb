require 'yaml'
require 'json'
require 'net/http'

class String
	# workaround for Ruby <1.9 not having `force_encoding`
	# http://stackoverflow.com/a/4585362/528645
	def to_utf8
		begin
			if (RUBY_VERSION.start_with?("1.8."))
				require 'iconv'
				::Iconv.conv('UTF-8//IGNORE', 'UTF-8', self + ' ')[0..-2]
				self
			else
				self.force_encoding("UTF-8")
			end
		rescue StandardError => e
			puts PrettyError.new("Couldn't force UTF-8 on string #{self}", e)
			self
		end
	end
end

class FileConfig
	@@path = File.join(File.dirname(__FILE__), *%w[/])
	@@config_file_path = @@path+"config/settings"

	def self.getConfig
		begin
			File.open(@@config_file_path, "r") do |f|
				hash = Hash.new
				f.read.lines.each {
					|line|
					if (!line.strip.empty? && line.include?(";=;"))
						key, value = line.split(";=;")
						hash[key.strip] = eval(value.strip)
					end
				}

				return hash
			end
		rescue StandardError => e
			return Hash.new
		end
	end

	def self.setValue(key, value)
		hash = self.getConfig
		hash[key] = value
		self.saveConfig(hash)
	end

	def self.saveConfig(hash)
		data = []

		hash.keys.each {
			|key|

			result = key+" ;=; "
			if (hash[key].kind_of?String)
				result = result+"\"#{hash[key]}\""
			else
				result = result+hash[key].to_s
			end

			data << result
		}

		File.open(@@config_file_path, "w") do |f|
			f.write(data.join("\n"))
		end
	end
end

class ListFile
	attr_accessor :path, :list

	def initialize(path)
		@path = path

		begin
			File.open(@path, "r") do
				|f|
				@list = f.readlines.collect {
					|line|
					line.strip if !line.strip.empty?
				}.compact
			end
		rescue
			@list = []
		end
	end

	def save
		File.open(@path, "w") do
			|f|
			f.write(@list.collect { |item| item.strip }.compact.uniq.join("\n"))
		end
	end

	def include?(str)
		return @list.collect{|one| one.downcase}.include?(str.downcase)
	end

	def self.overwrite(path, new_stuff)
		file = ListFile.new(path)
		if (new_stuff.kind_of?(Array))
			file.list = new_stuff
		else
			file.list << new_stuff.strip
		end
		file.save
	end
	
	def self.add_and_save(path, new_stuff)
		file = ListFile.new(path)
		if (new_stuff.kind_of?(Array))
			file.list = file.list.concat(new_stuff)
		else
			file.list << new_stuff.strip
		end
		file.save
	end
end

class LinkScanner
	def self.scan_for_rs_links(text)
		text.scan(/http\:\/\/(?:www\.)?rapidshare\.com\/files\/\d+?\/.*?[\s$\<\"\']/im).flatten.uniq
	end
	
	def self.scan_for_gf_links(text)
		text.scan(/http\:\/\/(?:www\.)?gamefront\.com\/files\/\d{8}/im).flatten.uniq
	end

	def self.scan_for_pl_links(text)
		text.scan(/http\:\/\/(?:www\.)?putlocker\.com\/file\/[a-z\d]{16}/im).flatten.uniq
	end
	
	def self.scan_for_bu_links(text)
		text.scan(/http\:\/\/(?:www\.)?billionuploads\.com\/[a-z\d]{12}/im).flatten.uniq
	end
	
	def self.get(links_of_interest) # deprecated, please use threaded version instead
		begin
			Lade.load_hosts
			
			groups = []
			groups += Rapidshare.check_urls(links_of_interest) || []
			groups += PutLocker.check_urls(links_of_interest) || []
			groups += BillionUploads.check_urls(links_of_interest) || []
			groups += GameFront.check_urls(links_of_interest) || []
			
			groups
		rescue StandardError => e
			puts PrettyError.new("Couldn't check the given links.", e, true)
			nil
		end
	end
	
	def self.threaded_get(links_of_interest, additional_params = nil)
		return Thread.new(links_of_interest) {
			|links_of_interest|
			
			groups = []
			begin
				Lade.load_hosts
				
				groups += Rapidshare.check_urls(links_of_interest) || []
				groups += PutLocker.check_urls(links_of_interest) || []
				groups += BillionUploads.check_urls(links_of_interest) || []
				groups += GameFront.check_urls(links_of_interest) || []
				
				if (additional_params)
					groups.each {
						|group|
						if (group.kind_of?(Hash) && additional_params.kind_of?(Hash))
							group.merge!(additional_params)
						end
					}
				end
			rescue StandardError => e
				puts PrettyError.new("Couldn't check the given links.", e, true)
			end
			
			Thread.current["groups"] = groups
		}
	end
	
	def self.scan_and_get(text) # deprecated, please use threaded version instead
		links = LinkScanner.scan_for_rs_links(text)
		links += LinkScanner.scan_for_bu_links(text)
		links += LinkScanner.scan_for_gf_links(text)
		links += LinkScanner.scan_for_pl_links(text)
		
		LinkScanner.get(links)
	end
	
	def self.threaded_scan_and_get(text, additional_params = nil)
		threads = []
				
		# a thread for each host
		threads << LinkScanner.threaded_get(LinkScanner.scan_for_rs_links(text), additional_params)
		threads << LinkScanner.threaded_get(LinkScanner.scan_for_bu_links(text), additional_params)
		threads << LinkScanner.threaded_get(LinkScanner.scan_for_gf_links(text), additional_params)
		threads << LinkScanner.threaded_get(LinkScanner.scan_for_pl_links(text), additional_params)
		
		threads
	end
	
	def self.get_download_link(file)
		result = catch(:stop) {
			throw(:stop) if file[:url].nil? || file[:url].empty?
			host = PutLocker if file[:url].downcase.include?("putlocker.com")
			host = GameFront if file[:url].downcase.include?("gamefront.com")
			host = BillionUploads if file[:url].downcase.include?("billionuploads.com")
			
			throw(:stop) if !host
			
			host.get_download_link(file)
		}
		
		result
	end
end

class Helper
	# bytes -> human readable size
	def self.human_size(n, base = 8)
		return "0" if n.nil?
		
		units = ["B", "KB", "MB", "GB"]
	
		unit = units[0]
		size = n
	
		if (n.instance_of?String)
			unit = n[-2, 2]
			size = n[0..-2].to_f
		end
	
		if ((size >= 1024 && base == 8) || (size >= 1000 && base == 10))
			human_size((base==8?(size/1024):(size/1000)).to_s+units[units.index(unit)+1], base)
		else
			if (size == size.to_i)
				return size.to_i.to_s+unit
			else
				index = size.to_s.index(".")
				
				return size.to_s[0..(index-1)]+unit if units.index(unit) < 2
				
				begin
					return size.to_s[0..(index+2)]+unit
				rescue
					return size.to_s[0..(index+1)]+unit
				end
			end
		end
	end
	
	# time -> minimalist date+time
	def self.human_time(time)
		time = Time.at(time.to_i) unless time.kind_of?(Time)
		twelveclock = false
		
		day = ""
		now = Time.now
		if (time.day != now.day || time.month != now.month || time.year != now.year)
			tmp = now-86400
			is_yesterday = (time.day == tmp.day && time.month == tmp.month && time.year == tmp.year)
	
			if (is_yesterday)
				day = "yesterday"
			else
				day = time.strftime("%-d %b")
			end
		end
	
		return day+" "+(twelveclock ? time.strftime("%I:%M%P") : time.strftime("%H:%M"))
	end
	
	# time -> relative
	def self.relative_time(time)
		time = Time.at(time.to_i) unless time.kind_of?(Time)
		
		now = Time.now
		diff = now - time
		hours_ago = (diff / 3600).to_i
		minutes_ago = (diff / 60).to_i
		
		hours_ago > 0 ? "#{hours_ago}h ago" : "#{minutes_ago}m ago"
	end
	
	def self.to_bytes(size)
		number = size.to_f
		unit = size.to_s.gsub(/[^a-zA-Z]/, "")

		return number.to_i if unit.empty?
		
		if (unit.downcase == "k" || unit.downcase == "kb")
			return (number*1024).to_i
		elsif (unit.downcase == "m" || unit.downcase == "mb")
			return (number*1024*1024).to_i
		elsif (unit.downcase == "g" || unit.downcase == "gb")
			return (number*1024*1024*1024).to_i
		else
			return number.to_i
		end
	end
	
	def self.escape_url(url)
		CGI.escape(url).gsub(" ", "%20").gsub("+", "%20")
	end
	
	def self.attempt(max_tries)
		return nil if max_tries < 1
		
		tries = 0
		begin
			yield
		rescue StandardError => e
			tries += 1
			if (tries < max_tries)
				retry
			else
				puts e.to_s
			end
		end
	end
	
	def self.attempt_and_raise(max_tries)
		return nil if max_tries < 1
		
		tries = 0
		begin
			yield
		rescue StandardError => e
			tries += 1
			if (tries < max_tries)
				retry
			else
				raise e
			end
		end
	end
	
	# Kinda like OpenURI's open(url), except it allows to limit fetch size
	# Solution found @ http://stackoverflow.com/a/8597459/528645
	def self.open_uri(url, limit = 102400)
		uri = URI(url)
		result = nil
		
		begin
			Net::HTTP.start(uri.host, uri.port) do |http|
				request = Net::HTTP::Get.new(uri.request_uri)
				http.request(request) do |response|
					result = response.instance_variable_get(:@socket).read(limit)
					http.finish
				end
			end
		rescue IOError
			# ignore
		end
		
		result
	end
end

class PrettyError
	def initialize(message = nil, exception = StandardError.new, full_backtrace = false)
		@message = message
		@exception = exception
		@full_backtrace = full_backtrace
	end
	
	def to_s
		lines = []
		lines << "*Additional message: "+@message if @message
		lines << "*Error: #{@exception}"
		
		if (@exception.backtrace)
			if (@full_backtrace)
				lines << "*Backtrace: \n\t"+@exception.backtrace.join("\n\t")
			else
				lines << "*Backtrace: "+@exception.backtrace.first
			end
		end

		"Caught Exception: #{@exception.class} {\n#{lines.join("\n")}\n}"
	end
end

class YAMLFile
	attr_reader :path
	attr_accessor :value
	
	def initialize(path)
		@path = path
		
		begin
			if (File.exist?(path))
				File.open(path, "r") do |f|
					@value = YAML.load(f.read) || []
				end
			else
				@value = []
			end
		rescue StandardError => e
			puts PrettyError.new("Error while loading YAML file", e, true)
		end
	end
	
	def <<(new_data)
		begin
			array = nil
			
			if (File.exist?(path))
				File.open(@path, "r") do |f|
					array = YAML.load(f.read)
				end
			end
			
			array = [] unless array.kind_of?(Array)
			
			if (new_data.kind_of?(Array))
				array = array + new_data
			else
				array << new_data
			end
			
			File.open(@path, "w") do |f|
				f.write(array.to_yaml)
			end
			
			@value = array
			
			true
		rescue StandardError => e
			puts PrettyError.new("Error while appending to YAML file '#{@path}'", e, true)
			false
		end
	end
	
	def overwrite(new_data)
		begin
			File.open(@path, "w") do |f|
				f.write(new_data.to_yaml)
			end
			
			@value = new_data
			
			true
		rescue StandardError => e
			puts PrettyError.new("Error while writing to YAML file '#{@path}'", e, true)
			false
		end
	end
	
	def save
		self.overwrite(@value)
	end
end

class ListSource
	def self.info
		{
			"pogdesign" => {
				:description => "If you have a <a href='http://pogdesign.co.uk/cat'>Pogdesign</a> account, you can add items from your filter list:"
			},
			"animecalendar" => {
				:description => "If you have an <a href='http://animecalendar.net/'>Animecalendar</a> account, you can add items from your filter list:"
			},
			"imdb_watchlist" => {
				:name => "IMDB Watchlist",
				:description => "If you have an <a href='http://imdb.com/'>IMDB</a> account, you can add items from your watchlist.<br>Make sure your watchlist is public and that you copy the correct user ID.<br>(e.g. <i>http://www.imdb.com/user/<b>ur23317856</b>/watchlist</i>)",
				:login_placeholder => "User ID (urXXXXXXXX)",
				:requires_password => false
			},
			"rottentomatoes_boxoffice" => {
				:name => "Box Office",
				:description => "Add movies from Rotten Tomatoes' Box Office list:",
				:requires_login => false,
				:requires_password => false
			},
			"rottentomatoes_upcomingmovies" => {
				:name => "Upcoming Movies",
				:description => "Add movies from Rotten Tomatoes' Upcoming Movies list:",
				:requires_login => false,
				:requires_password => false
			},
			"rottentomatoes_upcomingdvd" => {
			 	:name => "Upcoming DVDs",
			 	:description => "Add movies from Rotten Tomatoes' Upcoming DVDs list:",
			 	:requires_login => false,
			 	:requires_password => false
			 }
		}
	end
	
	def self.get(id, login = nil, password = nil)
		result = nil
		id = id.strip.downcase if id.kind_of?(String)
		method_available = (ListSource.methods(false).include?(id) || ListSource.methods(false).include?(id.to_sym)) # Ruby 1.8.7 lists methods as strings, newer versions lists them as symbols <_<
		
		if (id.kind_of?(String) && (id != "get") && (id != "info") && method_available)
			result = eval("ListSource.#{id.downcase}(login, password)")
		else
			result = "Unknown error!"
		end
		
		result.kind_of?(Array) ? {:list => result}.to_json : {:error => result}.to_json
	end
	
	def self.pogdesign(login, password)
		if login.nil? || password.nil? || login.empty? || password.empty?
			return "No login/password provided."
		end
		
		res = Net::HTTP.post_form(URI("http://www.pogdesign.co.uk/cat/"), 
		{:username => login, :password => password, :sub_login => "Account Login"})
		
		cookie = res.to_hash["set-cookie"]
		
		return "Invalid login/password." if (cookie.nil?)
		
		cookie = cookie.join("")
		
		res = Net::HTTP.new("www.pogdesign.co.uk").get("/cat/showselect.php", {"Cookie" => cookie})
		body = res.body
		
		checked = body.scan(/checkedletter(.*?)<\/div>/im).flatten.join("").scan(/>([^>]*?)<\/a>/im).flatten
		
		checked.collect! {
			|name|
			name.end_with?(" [The]") ? "The "+name.gsub(" [The]", "") : name
		}
		
		checked.uniq.sort
	end
	
	def self.animecalendar(login, password)
		if login.nil? || password.nil? || login.empty? || password.empty?
			return "No login/password provided."
		end
		
		http = Net::HTTP.new("animecalendar.net")
		
		res = http.get("/login")
		csrf_token = res.body.scan(/name=\"signin\[_csrf_token\]\" value=\"(.*?)\"/i).flatten.first
		cookie = res.to_hash["set-cookie"].join("")
		
		res = http.post("/login",
		"signin[username]=#{login}&signin[password]=#{password}&signin[_csrf_token]=#{csrf_token}",
		{'Cookie' => cookie, 'Referer' => 'http://animecalendar.net/login'})

		cookie = res.to_hash["set-cookie"]
		
		return "Invalid login/password." if (cookie.nil?)
		
		cookie = cookie.join("")
		
		res = Net::HTTP.new("animecalendar.net").get("/shows/filter", {"Cookie" => cookie})
		
		res.body.scan(/checked\">(.*?)<\/td>/im).flatten.collect{
			|item|
			item.strip.to_utf8
		}.uniq.sort
	end
	
	def self.imdb_watchlist(user_id, placeholder)
		res = Net::HTTP.new("www.imdb.com").get("/list/export?list_id=watchlist&author_id=#{user_id}")
		
		return "Invalid user ID." if res.code.to_i != 200
		
		titles = []
		lines = res.body.split("\n")
		lines.shift
		lines.each {
			|line|
			titles << line.split("\",\"")[5]
		}
		
		titles.sort
	end
	
	def self.rottentomatoes(method)
		k = "greezhtn4sga8txehjedvzyx".split("t").reverse.join("t")
		res = Net::HTTP.new("api.rottentomatoes.com").get("/api/public/v1.0/lists/#{method}.json?limit=25&page_limit=50&apikey=#{k}")
		
		return "Error. Please retry later." if res.code.to_i != 200
		
		movies = []
		begin
			json = JSON.parse(res.body.strip)
			json["movies"].each {
				|movie|
				movies << [movie["title"], movie["ratings"]["audience_score"].to_i]
			}
		rescue StandardError => e
			puts PrettyError.new("Error while parsing JSON for RottenTomatoes #{method}", e, true)
			return "Error. Please retry later."
		end
		
		if (method != "movies/box_office")
			movies = movies.sort_by { |title, audience_score| audience_score }.reverse
		end
		
		movies = movies.collect {
			|title, audience_score|
			title
		}
		
		movies
	end
	
	def self.rottentomatoes_boxoffice(placeholder, placeholder2)
		self.rottentomatoes("movies/box_office")
	end

	def self.rottentomatoes_upcomingmovies(placeholder, placeholder2)
		self.rottentomatoes("movies/upcoming")
	end
	
	def self.rottentomatoes_upcomingdvd(placeholder, placeholder2)
		self.rottentomatoes("dvds/upcoming")
	end
end