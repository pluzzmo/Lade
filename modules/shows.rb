class Shows
	@@shows_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/shows])
	@@website = "moc.daerhtesaeler".reverse # don't attract search engines!
	@@sm_url = "http://"+@@website+("lmx.1trap_tsop/".reverse) # sitemap url
	
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

		sitemap = Helper.open_uri(@@sm_url, 153600).to_s
		releases = sitemap.scan(/<loc>(http\:\/\/#{@@website.gsub(".", "\\.")}\/tv\-shows\/(.*?)\/)<\/loc>.*?<lastmod>(.*?)<\/lastmod>/im).uniq.take(50)
		
		releases.each {
			|url, release_name, lastmod|
			puts "Trying #{release_name}..."
			
			# Can't use parse().to_time in Ruby < 1.9
			fallback = ((DateTime.parse(lastmod).strftime("%s").to_i - Time.now.to_i) > 3600*2)
			
			# Checking to see if it's already downloaded
			episode_number = release_name.scan(/(.*?s\d\de\d\d(\-?e\d\d)?)-/).flatten
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
							puts e.backtrace.first
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
		sitemap = Helper.open_uri(@@sm_url, 153600).to_s
		releases = sitemap.scan(/<loc>http\:\/\/#{@@website.gsub(".", "\\.")}\/tv\-shows\/(.*?)\/<\/loc>/im).flatten.uniq.take(50)
		
		ListFile.overwrite(@@shows_cache_path, releases)
	end
	
	def self.check_page_for_relevant_links(source, release_names, page_name, fallback)
		source = source.scan(/<div\sclass=\"postarea\">(.*?)<div\sclass=\"clear\"/im).flatten
		source = source.first.gsub(/\n/, "").gsub(/<br\s?\/?>/, "").strip
		parts = source.split(/<hr\s*?\/?>/im)
		
		parts = parts[1..-1]
		
		wanted_release = nil
		release_names.each_index {
			|i|
			wanted_release = release_names[i] if release_names[i].include?("720p")
		}
		
		if (wanted_release.nil?)
			if (!fallback)
				puts "720p version still not uploaded... will check later..."
				return nil
			else
				puts "Couldn't find 720p version, falling back to anything else..."
				wanted_release = release_names.first
			end
		end
		
		relevant_part = parts[release_names.index(wanted_release)]
		if (!relevant_part || !relevant_part.include?(wanted_release))
			parts.each {
				|part|
				relevant_part = part if part.include?(wanted_release)
			}
		end
		
		groups = catch(:groups) {
			links = LinkScanner.scan_for_pl_links(relevant_part)
			groups = LinkScanner.get(links)
			throw(:groups, groups) unless links.empty? || groups.first[:dead]
			
			links = LinkScanner.scan_for_bu_links(relevant_part)
			groups = LinkScanner.get(links)
			throw(:groups, groups) unless links.empty?
			
			links = LinkScanner.scan_for_gf_links(relevant_part)
			groups = LinkScanner.get(links)
			throw(:groups, groups) unless links.empty? || groups.first[:dead]
			
			throw(:groups)
		}

		raise StandardError.new("No valid links found.") if groups.nil? || groups.empty?
		
		best_group = groups.first
		groups.each {
			|group|
			best_group = group if group[:size] > best_group[:size]
		}
		
		{
			:files => best_group[:files],
			:name => wanted_release,
			:reference => page_name
		}
	end
	
	def self.check_page_for_release_names(source, show_looking_for)
		source = source.scan(/<div\sclass=\"postarea\">(.*?)<div\sclass=\"clear\"/im).flatten

		raise StandardError.new("Couldn't find release info") if source.empty?
		
		# US release naming convention: show.name.S01E01
		us_regex = Regexp.new(show_looking_for.gsub(/\./, "[\\.\\s]")+"[\\.\\s]S\\d\\dE\\d\\d.*", true)
		# UK release naming convention: show_name.1x01
		uk_regex = Regexp.new(show_looking_for.gsub(/\./, "[_\\s]")+"[\\.\\s]\\d\\d?.{1,2}\\d\\d.*", true)
		
		source = source.first.gsub(/\n/, "").gsub(/<br\s?\/?>/, "").strip
		bolded_parts = source.scan(/<strong>(.*?)<\/strong>/).flatten
		release_names = []
		
		bolded_parts.each {
			|part|
			
			release_names << part.scan(us_regex)
			release_names << part.scan(uk_regex)
		}
		
		release_names = release_names.flatten.uniq.compact
		
		raise StandardError.new("No releases are uploaded yet...") if release_names.empty?
		
		release_names
	end
	
	def self.on_demand
		result = []
		
		sitemap = (open @@sm_url).read.to_s
		releases = sitemap.scan(/<loc>(http\:\/\/#{@@website.gsub(".", "\\.")}\/tv\-shows\/(.*?)\/)<\/loc>.*?<lastmod>(.*?)<\/lastmod>/im).take(200)
		
		releases.each {
			|url, release_name, lastmod|
			
			formatted_name = release_name.gsub(/-|_|\./, " ")

			parts = formatted_name.split(" ").compact
			
			parts = parts.collect {
				|word|
				word = word.capitalize unless ["and", "of", "with", "in", "x264"].include?(word)
				word = word.upcase if ["au", "us", "uk", "ca", "hdtv", "xvid", "pdtv", "web", "dl"].include?(word.downcase)
				word = word.upcase if word =~ /s\d\de\d\d/i
				word
			}
			
			parts << parts.pop.upcase unless parts.empty?
			
			formatted_name = parts.join(" ")
			
			result << [formatted_name, release_name]
		}
		
		result
	end
	
	def self.download_on_demand(reference)
		source = (open "http://#{@@website}/tv-shows/#{CGI.escape(reference)}").read.to_s
		
		link_groups = LinkScanner.scan_and_get(source)
		best_group = self.best_group(link_groups)
		
		result = []
		link_groups.each {
			|group|
			
			formatted_name = group[:name]+" - "+Helper.human_size(group[:size], 8)
			
			url = group[:files].first[:url].downcase
			host = ""
			suffix = ""
			
			if (url.include?("putlocker.com"))
				host = "PutLocker: "
				suffix = "pl"
			elsif (url.include?("billionuploads.com"))
				host = "BillionUploads: "
				suffix = "bu"
			elsif (url.include?("gamefront.com"))
				host = "GameFront: "
				suffix = "gf"
			end

			formatted_name = host + formatted_name + (group == best_group ? " (recommended)" : "")
			new_reference = "#{reference}/#{group[:name]}#{':'+suffix unless suffix.empty?}"
			
			if (group[:dead])
				formatted_name = "DEAD - "+formatted_name
				new_reference = reference
			end
			
			result << [formatted_name, new_reference] 
		}
		
		result
	end
	
	
	def self.download_on_demand_step2(reference)
		source = (open "http://#{@@website}/tv-shows/#{CGI.escape(reference.first)}").read.to_s
		reference.push(reference.pop.split(":"))
		reference.flatten!
		
		link_groups = []
		host_domain = ""
		
		case reference.last
		when "pl"
			host_domain = "putlocker.com"
			link_groups = LinkScanner.get(LinkScanner.scan_for_pl_links(source))
		when "bu"
			host_domain = "billionuploads.com"
			link_groups = LinkScanner.get(LinkScanner.scan_for_bu_links(source))
		when "gf"
			host_domain = "gamefront.com"
			link_groups = LinkScanner.get(LinkScanner.scan_for_gf_links(source))
		end

		wanted_group = nil
		
		link_groups.each {
			|group|
			url = group[:files].first[:url].downcase

			if (reference[1] == group[:name] && url.include?(host_domain) && !group[:dead])
				wanted_group = group
				break
			end
		}
		
		if (!wanted_group.nil?)
			[{:files => wanted_group[:files], :reference => reference.first}]
		end
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
		"Downloads US & UK TV shows from <a href=\"http://#{@@website}\">#{@@website}</a> via direct links (PutLocker/BillionUploads/GameFront). Has most airing shows."
	end
	
	def self.broken?
		false
	end
	
	def self.best_group(file_groups)
		groups = file_groups.compact.collect {
			|group|
			group unless group[:dead]
		}.compact.sort {
			|group_a, group_b|
			
			size_a = group_a.nil? ? 0 : group_a[:size]
			size_b = group_b.nil? ? 0 : group_b[:size]
			
			if (size_b == 0 || size_a == 0)
				size_b <=> size_a
			else
				a_is_putlocker = group_a[:files].first[:url].downcase.include?("putlocker.com") ? true : false
				b_is_putlocker = group_b[:files].first[:url].downcase.include?("putlocker.com") ? true : false
				
				if (a_is_putlocker != b_is_putlocker)
					a_is_putlocker ? size_b <=> size_a+5242880 : size_b+5242880 <=> size_a
				else
					size_b <=> size_a
				end
			end
		}
		
		groups.first
	end
end