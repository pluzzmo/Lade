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
		text.scan(/http\:\/\/(?:www\.)?rapidshare\.com\/files\/\d+?\/.*?[\s$\<\"\']/im).uniq.flatten
	end
	
	def self.scan_for_bu_links(text)
		text.scan(/http\:\/\/(?:www\.)?billionuploads\.com\/[a-z\d]{12}/im).uniq.flatten
	end
	
	def self.scan_for_pl_links(text)
		text.scan(/http\:\/\/(?:www\.)?putlocker\.com\/file\/[a-z\d]{16}/im).uniq.flatten
	end
	
	def self.scan_for_zdoox_links(text)
		found = []
		text.scan(/zdoox\.com\/firm\/\d+/im).uniq.flatten.collect {
			|zdoox|
			zdoox = zdoox.gsub("/firm/", "/firm/m1.php?id=") unless zdoox.include?("m1.php")
			source = (open ("http://"+zdoox)).read.to_s
			links = source.scan(/NewWindow\(\'(.*?)\'/im)
			found << links
		}
		
		found.compact.flatten.uniq
	end
end

class Helper
	# bytes -> human readable size
	def self.human_size(n, base)
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
				puts e.backtrace.first
				puts e.to_s
			end
		end
	end
end