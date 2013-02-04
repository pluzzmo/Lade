class Shows
	@@shows_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/shows])

	def self.run(to_download, already_downloaded, max)
		result = []
		remaining = max
		shows = to_download.list.collect {
			|name|
			name.downcase.gsub(" ", "-").gsub("'", "")
		}
		
		already_downloaded = already_downloaded.collect {
			|item|
			[item, item.scan(/(.*?s\d\de\d\d(e\d\d)?)-/)]
		}.flatten.compact
				
		shows_cache = ListFile.new(@@shows_cache_path)

		sitemap = (open "http://www.myrls.me/sitemap.xml").read.to_s
		releases = sitemap.scan(/\<loc\>(http\:\/\/www\.myrls\.me\/tv\/shows\/(.*?)\/)\<\/loc\>.*?\<lastmod\>(.*?)\<\/lastmod\>/im).take(50)
		
		releases.each {
			|url, release_name, lastmod|
			puts "Trying #{release_name}..."
			
			# Can't use parse().to_time in Ruby < 1.9
			fallback = ((DateTime.parse(lastmod).strftime("%s").to_i - Time.now.to_i) > 3600*2)
			
			# Checking to see if it's already downloaded
			episode_number = release_name.scan(/(.*?s\d\de\d\d(e\d\d)?)-/).flatten
			episode_number = (episode_number.empty? ? nil : episode_number.first)
			
			if already_downloaded.include?(release_name)
				puts "Already downloaded."
			elsif already_downloaded.include?(episode_number)
				puts "Episode already downloaded."
			elsif shows_cache.include?(release_name)
				puts "Released before first-time setup, won't check."
			else
				shows.each {
					|show|
					if (release_name.start_with?(show))
						begin
							page = (open url).read.to_s
							
							release_names = self.check_page_for_release_names(page, show.gsub("-", "."))
							links = self.check_page_for_relevant_links(page, release_names, release_name, fallback)
							
							if (!links.nil?)
								result << links
								remaining = remaining - 1
							end
							
							break
						rescue StandardError => e
							puts e.to_s
						end
					end
				}
			end

			break if remaining < 1
		}
		
		return result
	end
	
	def self.always_run
	end
	
	def self.install
		sitemap = (open "http://www.myrls.me/sitemap.xml").read.to_s
		releases = sitemap.scan(/\<loc\>(http\:\/\/www\.myrls\.me\/tv\/shows\/(.*?)\/)\<\/loc\>/).take(50).collect {
			|url, release_name|
			release_name
		}
		
		ListFile.overwrite(@@shows_cache_path, releases)
	end
	
	def self.check_page_for_relevant_links(source, release_names, page_name, fallback)
		zdoox_links_txt = LinkScanner.scan_for_zdoox_links(source).join("\n")
		found_links = LinkScanner.scan_for_pl_links(source)
		found_links += LinkScanner.scan_for_pl_links(zdoox_links_txt)
		link_groups = PutLocker.check_urls(found_links)

		# skip for now, not all releases have been uploaded yet
		# if fallback = true (page is older than 1 hour) and not all files have been uploaded, download the one with the most links anyway
		if release_names.count > link_groups.count && !fallback
			puts "Still not uploaded... will check later..."
			return nil
		end
		
		# the HD version is the biggest collection of files in terms of filesize
		biggest_group = link_groups[0]
		link_groups.each {
			|group|
			biggest_group = group if group[:size] > biggest_group[:size]
		}
		
		if (biggest_group[:dead])
			puts "Links dead... skipping"
			return nil
		end
		
		links = biggest_group[:files].collect {
			|file|
			PutLocker.get_download_link(file)
		}
		
		release_name = release_names.collect {
			|rn|
			rn if rn.downcase.include?("720p")
		}.compact[0]
		
		filenames = links.collect {
			|link|
			filename = link.split("/").last
			filename.gsub(/.*?((\.part\d+)?\.rar)/, "#{release_name}"+'\1')
		}
		
		return {:type => 0, :links => links, :filenames => filenames, :reference => page_name}
	end
	
	def self.check_page_for_release_names(source, show_looking_for)
		entry = source.scan(/\<div\sclass\=\"(?:(?:entry(?:\-content)?)|post)\"\>(.*?)\<div\sclass\=\"(?:clear|usenet)\"/im).flatten
		
		raise StandardError.new("Couldn't find release info") if entry.empty?
		
		# US release naming convention: show.name.S01E01
		us_regex = Regexp.new(show_looking_for.gsub(/\./, "[\\.\\s]")+"[\\.\\s]S\\d\\dE\\d\\d.*", true)
		# UK release naming convention: show_name.1x01
		uk_regex = Regexp.new(show_looking_for.gsub(/\./, "[_\\s]")+"[\\.\\s]\\d\\d?.{1,2}\\d\\d.*", true)
		
		entry = entry[0].gsub(/\n/, "").gsub(/\<br\s?\/?\>/, "").strip
		bolded_parts = entry.scan(/\<strong\>(.*?)\<\/strong\>/).flatten
		release_names = []
		
		bolded_parts.each {
			|part|
			
			release_names << part.scan(us_regex)
			release_names << part.scan(uk_regex)
		}
		
		release_names = release_names.flatten.compact
		release_names_720p = release_names.collect {
			|rn|
			rn if rn.downcase.include?("720p")
		}.compact
		
		raise StandardError.new("Couldn't find any relevant releases") if release_names_720p.empty?
		
		release_names
	end
	
	def self.on_demand
		result = []
		
		sitemap = (open "http://www.myrls.me/sitemap.xml").read.to_s
		releases = sitemap.scan(/\<loc\>(http\:\/\/www\.myrls\.me\/tv\/shows\/(.*?)\/)\<\/loc\>.*?\<lastmod\>(.*?)\<\/lastmod\>/im).take(50)
		
		releases.each {
			|url, release_name, lastmod|
			
			formatted_name = release_name.gsub(/-|_|\./, " ")

			parts = formatted_name.split(" ").compact
			
			parts = parts.collect {
				|word|
				word = word.capitalize unless ["and", "of", "with", "in", "x264"].include?(word)
				word = word.upcase if ["au", "us", "uk", "ca", "hdtv", "xvid", "pdtv"].include?(word.downcase)
				word = word.upcase if word =~ /s\d\de\d\d/i
				word
			}
			
			parts << parts.pop.upcase unless parts.empty?
			
			formatted_name = parts.join(" ")
			
			result << [formatted_name, release_name]
		}
		
		return result
	end
	
	def self.download_on_demand(reference)
		source = (open "http://www.myrls.me/tv/shows/#{CGI.escape(reference)}").read.to_s
		
		zdoox_links_txt = LinkScanner.scan_for_zdoox_links(source).join("\n")
		found_links = LinkScanner.scan_for_pl_links(source)
		found_links += LinkScanner.scan_for_pl_links(zdoox_links_txt)
		link_groups = PutLocker.check_urls(found_links)
		
		result = []
		link_groups.each {
			|group|
			
			formatted_name = group[:name]+" - "+Helper.human_size(group[:size], 8)
			new_reference = "#{reference}/#{group[:name]}"
			
			if (group[:dead])
				formatted_name = "DEAD - "+formatted_name
				new_reference = reference
			end
			
			result << [formatted_name, new_reference] 
		}
		
		result
	end
	
	
	def self.download_on_demand_step2(reference)
		source = (open "http://www.myrls.me/tv/shows/#{CGI.escape(reference.first)}").read.to_s
		
		zdoox_links_txt = LinkScanner.scan_for_zdoox_links(source).join("\n")
		found_links = LinkScanner.scan_for_pl_links(source)
		found_links += LinkScanner.scan_for_pl_links(zdoox_links_txt)
		link_groups = PutLocker.check_urls(found_links)
		
		# the HD version is the biggest collection of files in terms of filesize
		wanted_group = nil
		
		link_groups.each {
			|group|
			wanted_group = group if (reference.last == group[:name])
		}
		
		links = wanted_group[:files].collect {
			|file|
			PutLocker.get_download_link(file)
		}
		
		filenames = links.collect {
			|link|
			link.split("/").last
		}
		
		return [{:type => 0, :links => links, :filenames => filenames, :reference => reference.first}]
	end
	
	def self.settings_notice
		"Type one show name per line.
		
		<b>Example:</b>
		Breaking Bad
		The Big Bang Theory
		The Walking Dead
		Two and a Half Men"
	end
	
	def self.has_on_demand?
		true
	end
	
	def self.description
		"Downloads US & UK TV shows from <a href=\"http://myrls.me\">MyRLS.me</a> via direct links (PutLocker). Has most airing shows except a few obscure ones."
	end
	
	def self.broken?
		false
	end

	def self.update_url
		nil
	end
end