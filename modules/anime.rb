class Anime
	@@anime_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/anime])
	
	def self.items_for_dir(path = "/wat/Anime/")
		return [] unless path.start_with?("/wat/Anime/") && path.end_with?("/")
		
		result = []
		tentaclenoises = (open "http://tentaclenoises.co.uk"+path).read
		items = tentaclenoises.scan(/\<a\shref\=\"(.*?)\"\>(.*?)\<\/a\>/im)
		
		items.each {
			|item|
			
			next if item.last == "[To Parent Directory]"
			
			if (item.first.end_with?("/"))
				result = result + self.items_for_dir(item.first)
			else
				result << [item.first, item.last]
			end
		}
		
		result
	end
	
	def self.run(to_download, already_downloaded, max)
		result = []
		remaining = max
		
		items = self.items_for_dir
		
		anime_cache = ListFile.new(@@anime_cache_path)
		
		items.each {
			|item|
			
			puts "Trying #{item.last}..."

			# Get the name
			name = item.last
			name = name.gsub(/\[.*?\]/, "") # remove checksums, resolution and fansub name
			name = name.gsub(/(\.mkv)|(\.avi)|(\.mp4)$/, "") # remove extension
			name = name.gsub("_", " ").gsub(/\s\-\s.*?$/, "").strip

			should_download = to_download.include?(name)
			old_release = already_downloaded.include?(item.last) || anime_cache.include?(item.last)
			
			if (should_download && !old_release)
				file = {:download => "http://tentaclenoises.co.uk"+item.first, :filename => item.last}
				result << {:files => [file], :reference => item.last}
				remaining = remaining - 1
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
		items = self.items_for_dir.collect {
			|item|
			item.last
		}
		
		ListFile.overwrite(@@anime_cache_path, items)
	end
	
	def self.settings_notice
		items = self.items_for_dir
		
		names = items.collect {
			|item|
			
			# Get the name
			name = item.last
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
		return self.items_for_dir.collect {
			|item|
			[item.last, item.last]
		}
	end
	
	def self.download_on_demand(reference)
		result = []

		items = self.items_for_dir
				
		items.each {
			|item|

			if (reference == item.last)
				file = {:download => "http://tentaclenoises.co.uk"+item.first, :filename => item.last}
				result << {:files => [file], :reference => item.last}
			end
		}
		
		result
	end
	
	def self.description
		"Downloads english-subbed anime in 720p from <a href='http://tentaclenoises.co.uk/wat/Anime/'>Tentacle Noises</a> via direct links. Has most airing anime except a few."
	end
	
	def self.broken?
		false
	end
end