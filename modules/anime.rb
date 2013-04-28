class Anime
	@@anime_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/anime])
	@@debug = false
	
	def self.thread_for_dir(path, list_only = true)
		return Thread.new(path, list_only) {
			|path, list_only|
			tentaclenoises = (open "http://tentaclenoises.co.uk"+path).read.to_s.force_encoding("UTF-8")
			items = tentaclenoises.scan(/(\d+|&lt;dir&gt;)\s\<a\shref\=\"(.*?)\"\>(.*?)\<\/a\>/im)
			
			result = []
			dirs = []
			
			items.each {
				|item|
				
				next if item.last == "[To Parent Directory]"

				# limit folder depth at 1
				if item[1].end_with?("/") && path == "/wat/Anime/"
					dirs << item[1]
					next
				end
				
				if (list_only)
					result << [item[1], item.last] 
				else
					file = {
						:name => item.last,
						:size => item.first.to_i,
						:url => "http://tentaclenoises.co.uk"+item[1],
						:download => "http://tentaclenoises.co.uk"+item[1] }
					group = {
						:name => item.last,
						:reference => item.last,
						:size => item.first.to_i,
						:files => [file] }
					result << group
				end
			}
			
			Thread.current["dirs"] = dirs
			list_only ? Thread.current["list"] = result : Thread.current["groups"] = result
		}
	end

	def self.threads_for_fetching(list_only = true)
		root_dir_thread = self.thread_for_dir("/wat/Anime/", list_only)
		root_dir_thread.join
		
		threads = []
		threads << root_dir_thread
		
		if (root_dir_thread["dirs"])
			root_dir_thread["dirs"].each {
				|dir|
				threads << self.thread_for_dir(dir, list_only)
			}
		end
		
		threads
	end
	
	def self.available_files(only_names = true)
		result = []
		
		threads = self.threads_for_fetching(true)
		threads.each {
			|thread|
			thread.join
			
			if (only_names)
				thread["list"].collect {
					|entry|
					result << entry.last
				}
			else
				result += thread["list"]
			end
		}
		
		result
	end

	def self.run(to_download, already_downloaded, max)
		result = []
		remaining = max
		
		anime_cache = ListFile.new(@@anime_cache_path)
		
		items = self.available_files(false)
		items.each {
			|item|
			
			puts "Trying #{item.last}..." if @@debug

			# Get the name & episode number
			name = item.last
			name = name.gsub(/\[.*?\]/, "") # remove checksums, resolution and fansub name
			name = name.gsub(/(\.mkv)|(\.avi)|(\.mp4)$/i, "") # remove extension
			name = name.gsub("_", " ")
			
			ep_number = name.scan(/\s-\s(\d+)/).flatten.uniq.first
			name = name.gsub(/\s\-\s.*?$/, "").strip
			
			should_download = to_download.include?(name)
			old_release = already_downloaded.include?(item.last) || anime_cache.include?(item.last)
			
			if (should_download && !old_release)
				# now check if that episode was already downloaded with a different release name
				ep_already_downloaded = false
				if (ep_number)
					(already_downloaded+anime_cache.list).each {
						|rls_name|
						name2 = rls_name.gsub(/\[.*?\]/, "").gsub(/(\.mkv)|(\.avi)|(\.mp4)$/i, "")
						name2 = name2.gsub("_", " ")
						rls_ep_number = name2.scan(/\s-\s(\d+)/).flatten.uniq.first
						name2 = name2.gsub(/\s\-\s.*?$/, "").strip
						
						if (name2 == name && rls_ep_number == ep_number)
							ep_already_downloaded = true
							puts "Episode (#{ep_number}) already downloaded on a different release (#{rls_name})" if @@debug
							break
						end
					}
				end
				
				if (ep_number.nil? || !ep_already_downloaded)
					file = {:download => "http://tentaclenoises.co.uk"+item.first, :filename => item.last}
					result << {:files => [file], :reference => item.last}
					remaining = remaining - 1
				end
			end

			break if remaining < 1
		}
		
		if (result.empty?)
			# update cache here in order to avoid unnecessary http requests
			# that would have occured if we let Lade handle it through the method 'update_cache'
			files = items.collect {
				|item| item.last
			}
			
			ListFile.add_and_save(@@anime_cache_path, files)
		end
		
		result
	end	

	def self.settings_notice
		"Type one anime name per line.
		
		<b>Example:</b>
		Sword Art Online
		Chuunibyou Demo Koi ga Shitai!
		Naruto Shippuuden
		Little Busters!
		
		<b>Currently available animes:</b>"
	end
	
	def self.list_sources
		# load list of currently available animes from cache instead of fetching from the website and making the user wait for the settings page to load
		files = ListFile.new(@@anime_cache_path).list
		
		names = files.collect {
			|name|
			
			# get anime name
			name = name.gsub(/\[.*?\]/, "") # remove checksums, resolution and fansub name
			name = name.gsub(/(\.mkv)|(\.avi)|(\.mp4)$/, "") # remove extension
			name = name.gsub("_", " ").gsub(/\s\-\s.*?$/, "").strip # remove ep numbers
			name = nil if name =~ /\.(zip|rar)$/
			
			name
		}.compact.uniq.sort
		
		["animecalendar", names]
	end
	
	def self.has_on_demand?
		true
	end
	
	def self.on_demand(reference = nil)
		self.threads_for_fetching(false)
	end
	
	def self.description
		"Downloads english-subbed anime in 720p from <a href='http://tentaclenoises.co.uk/wat/Anime/'>Tentacle Noises</a> via direct links. Has most airing anime except a few."
	end
	
	def self.broken?
		false
	end
end