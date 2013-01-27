class Anime
	@@anime_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/anime])
	
	def self.run(to_download, already_downloaded, max)
		result = []
		remaining = max
		
		tentaclenoises = (open "http://tentaclenoises.co.uk/wat/Anime/").read
		items = tentaclenoises.scan(/\<br\>(.*?)\s\d+?\s\<a\shref\=\"(.*?)\"\>(.*?)\<\/a\>/im)
		
		anime_cache = ListFile.new(@@anime_cache_path)
		
		items.each {
			|item|
			
			puts "Trying #{item[2]}..."
			
			# Get the date the file was uploaded
			begin
				datetime = item[0].gsub("<br>", "").split(" ")
				datetime[0] = datetime[0].split("/")
				datetime[0] = datetime[0].insert(1, datetime[0].shift).join("/")
				datetime = datetime.join(" ")
				
				time_uploaded = DateTime.parse(datetime+" +0800").to_time
			rescue Exception => e
				puts e.to_s
			end

			# Get the name
			name = item[2]
			name = name.gsub(/\[.*?\]/, "") # remove checksums, resolution and fansub name
			name = name.gsub(/(\.mkv)|(\.avi)|(\.mp4)$/, "") # remove extension
			name = name.gsub("_", " ").gsub(/\s\-\s.*?$/, "").strip

			should_download = to_download.include?(name)
			old_release = already_downloaded.include?(item[2]) || anime_cache.include?(item[2])
			# incomplete = !((Time.now - time_uploaded > 1800) || time_uploaded.nil?)
			
			if (should_download && !old_release)# && !incomplete)
				result << {:type => 0,
					:links => ["http://tentaclenoises.co.uk"+item[1]],
					:filenames => [item[2]],
					:file => item[2],
					:reference => item[2]}

				remaining = remaining - 1
			#elsif (should_download && incomplete)
			#	puts "* Might be incomplete, will try later."
			end

			break if remaining < 1
		}
		
		return result
	end	

	def self.always_run
		if (!File.exists?(@@anime_cache_path))
			Anime.update_cache
		end
	end
	
	def self.update_cache
		tentaclenoises = (open "http://tentaclenoises.co.uk/wat/Anime/").read
		items = tentaclenoises.scan(/\d+?\s\<a\shref\=\".*?\"\>(.*?)\<\/a\>/im).flatten.uniq
		
		ListFile.overwrite(@@anime_cache_path, items)
	end
	
	def self.settings_notice
		tentaclenoises = (open "http://tentaclenoises.co.uk/wat/Anime/").read
		items = tentaclenoises.scan(/\<br\>(.*?)\s\d+?\s\<a\shref\=\"(.*?)\"\>(.*?)\<\/a\>/im)
		
		names = items.collect {
			|item|
			
			# Get the name
			name = item[2]
			name = name.gsub(/\[.*?\]/, "") # remove checksums, resolution and fansub name
			name = name.gsub(/(\.mkv)|(\.avi)|(\.mp4)$/, "") # remove extension
			name = name.gsub("_", " ").gsub(/\s\-\s.*?$/, "").strip
			name = nil if name =~ /\.(zip|rar)$/
			
			name
		}.compact.uniq
		
		"Type one anime name per line.
		
		<b>Example:</b>
		Sword Art Online
		Chuunibyou Demo Koi ga Shitai!
		Naruto Shippuuden
		Little Busters!
		
		<b>Currently available animes (click to add):</b>
		"+names.collect {
			|name|
			"<a onclick=\"add('#{name}');\">#{name}</a>"
		}.join("\n")
	end
	
	def self.has_on_demand?
		true
	end
	
	def self.on_demand
		result = []
		
		tentaclenoises = (open "http://tentaclenoises.co.uk/wat/Anime/").read
		items = tentaclenoises.scan(/\<br\>(.*?)\s\d+?\s\<a\shref\=\"(.*?)\"\>(.*?)\<\/a\>/im)
		
		items.each {
			|item|

			result << [item[2], item[2]]
		}
		
		return result
	end
	
	def self.download_on_demand(reference)
		result = []

		tentaclenoises = (open "http://tentaclenoises.co.uk/wat/Anime/").read
		items = tentaclenoises.scan(/\<br\>(.*?)\s\d+?\s\<a\shref\=\"(.*?)\"\>(.*?)\<\/a\>/im)
				
		items.each {
			|item|

			if (reference == item[2])
				result << {:type => 0,
					:links => ["http://tentaclenoises.co.uk"+item[1]],
					:filenames => [item[2]],
					:file => item[2],
					:reference => item[2]}
			end
		}
		
		return result
	end
	
	def self.description
		"Downloads english-subbed anime in 720p from <a href='http://tentaclenoises.co.uk/wat/Anime/'>Tentacle Noises</a> via direct links. Has most airing anime except a few."
	end
	
	def self.broken?
		false
	end

	def self.update_url
		nil
	end
end