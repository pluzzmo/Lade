class Movies
	@@movies_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/movies])
	@@source_page = "http://publichd.se/index.php?page=torrents&active=1&category=2;5;15;16"
	@@debug = false
	
  def self.run(to_download, already_downloaded, max)
	  result = []
	  remaining = max
		
		movies_cache = ListFile.new(@@movies_cache_path)
		
		source = open(@@source_page).read.to_s.force_encoding("UTF-8")
		source += open(@@source_page+"&pages=2").read.to_s.force_encoding("UTF-8")
		
		items = source.scan(/\"download\.php\?id=([0-9a-f]+)&amp;f=(.*?)\"/im).collect {
			|id, name|
			[id, CGI.unescape(name)]
		}
		
		items.each {
			|torrent_id, torrent_name|
			
			puts "Trying #{torrent_name}..." if @@debug
			
			# skip if already downloaded
			if already_downloaded.include?(torrent_id) || movies_cache.include?(torrent_id)
				puts "Already downloaded." if @@debug && already_downloaded.include?(torrent_id)
				next
			end
			
			c_torrent_name = torrent_name.gsub(".", " ").gsub(/\s{2,}/, " ").strip # cleaning
			
			to_download.list.each {
				|list_item|
				list_item = list_item.dup
				
				criteria = []
				["720p", "1080p", "bluray", "brrip", "xvid"].each {
					|reg|
					criteria << reg if list_item.gsub!(Regexp.new(reg, true), "")
				}
				criteria.compact!
				
				if criteria.empty?
					criteria += ["720p", "bluray"]  # default to 720p bluray if unspecified
				end
				
				list_item = list_item.gsub(/\s{2,}/, " ").strip
				
				if (c_torrent_name.downcase.start_with?(list_item.downcase)) # movie name matches
					puts "Movie name matches..." if @@debug
					
					# now we need to match the criteria
					matches = true
					criteria.each { |one|
						matches = false unless c_torrent_name.downcase.include?(one.downcase)
					}
					
					if (matches) # movie & quality matches! we'll start the download
						puts "Quality OK" if @@debug
						
						file = {
							:download => "http://publichd.se/download.php?id="+torrent_id,
							:filename => torrent_name
						}
								
						result << {:files => [file], :reference => torrent_id}
						
						remaining = remaining - 1
						break
					end
				end
			}
			
			break if remaining < 1
		}
		
		result
  end
  
	def self.always_run
		if (!File.exists?(@@movies_cache_path))
			Movies.update_cache
		end
	end
	
	def self.update_cache
		source = open(@@source_page).read.to_s.force_encoding("UTF-8")
		ids = source.scan(/\"download\.php\?id=([0-9a-f]+)&amp;/im).flatten.uniq.compact
		
		ListFile.overwrite(@@movies_cache_path, ids) unless ids.empty?
	end
	
	def self.has_on_demand?
		true
	end
	
	def self.on_demand(reference = nil)
		# no threading because it's favorable to have an ordered new-to-old list
		# like the one that appears in the website
		
		source = open(@@source_page).read.to_s.force_encoding("UTF-8")
		source += open(@@source_page+"&pages=2").read.to_s.force_encoding("UTF-8")
		
		groups = []
		trs = source.scan(/<tr>.*?<\/tr>/im)
		trs.each {
			|tr|
			
			torrent = tr.scan(/\"download\.php\?id=([0-9a-f]+)&amp;f=(.*?)\"/im).flatten.compact.uniq
			if (!torrent.empty?)
				size = tr.scan(/width=\"55\"><b>(.*?)<\/b>/).flatten.compact.uniq.first
				torrent << CGI.unescape(torrent.last)
				
				groups << {
					:name => torrent.last.gsub(/\.torrent$/, ""),
					:reference => torrent.first,
					:size => Helper.to_bytes(size),
					:host => "Torrent",
					:files => [{
						:download => "http://publichd.se/download.php?id="+torrent.first,
						:filename => torrent.last,
						:size => Helper.to_bytes(size)
					}]
				}
			end
		}
		
		groups
	end

	def self.settings_notice
		"Type one <b>movie name</b> per line.
		
		Specify the quality if you want something other than 720p Bluray.
		Available types: <i>720p, 1080p, bluray, brrip</i> and <i>xvid</i>
		
		<b>Example:</b>
		Iron Man 3 1080p Bluray
		Oblivion 720p brrip
		Man of Steel xvid"
	end
	
	def self.list_sources
		["imdb_watchlist", "rottentomatoes_boxoffice", "rottentomatoes_upcomingmovies", "rottentomatoes_upcomingdvd"]
	end

	def self.description
		"Downloads <b>torrent</b>s of high quality movies from <a href=\"http://publichd.se\">PublicHD.se</a>."
	end
	
	def self.broken?
		false
	end
end