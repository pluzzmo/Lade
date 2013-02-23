class Eztv
	@@eztv_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/eztv])
	
	def self.run(to_download, already_downloaded, max)
		shows = to_download.list.collect {
			|name|
			name.downcase.gsub("'", "")
		}
		
		begin
			first = shows.first.downcase
			hd = (first.include?("true") || first.include?("yes"))
			pop = (!hd && (first.include?("false") || first == "no"))
		rescue StandardError => e
			hd = true
		end
		
		shows = shows.pop(shows.count-1) if pop
		
		cache_id = 0
		Helper.attempt_and_raise(2) {
			File.open(@@eztv_cache_path, "r") do |f|
				cache_id = f.read.strip.to_i
			end
			
			if (cache_id < 41000)
				cache_id = Eztv.update_cache
			end
		}
		
		result = []
		remaining = max

		page = nil
		Helper.attempt_and_raise(3) {
			page = open("http://eztv.it/").read.to_s
		}
		
		items = page.scan(/<tr\sname=\"hover\"\sclass=\"forum_header_border\">(.*?)<\/tr>/im).flatten.uniq
		
		items.each {
			|item|
			
			reference = item.scan(/\/ep\/(\d+)\//im).flatten.uniq.first
			name = item.scan(/class=\"epinfo\">(.*?)<\/a>/im).flatten.uniq.first
			
			shows.each {
				|show|
				
				is_hd = name.downcase.include?("720p")
				matches_setting = (hd && is_hd) || (!hd && !is_hd)
				
				if (name.downcase.start_with?(show) && matches_setting && !already_downloaded.include?(reference) && cache_id < ref.to_i)
					links = item.scan(/<a\shref=\"([^\"]*?)\"\sclass=\"download_\d\"/im).flatten.uniq
					link = nil
					
					# Get mirror links if the main one is down
					links.each {
						|mirror|
						
						begin
							link = mirror unless open(mirror).nil?
						rescue StandardError => e
						end
						
						break if (!link.nil?)
					}
					
					
					if (link.nil?)
						puts "Couldn't get .torrent!"
					else
						file = {:download => link, :filename => name+".torrent"}
						result << {:files => [file], :reference => reference}
						
						remaining = remaining - 1
					end
				end
			}
			
			break if remaining < 1
		}
		
		result
	end
  
  def self.always_run
  	if (!File.exist?(@@eztv_cache_path))
  		Eztv.update_cache
  	end
  end
	
	def self.update_cache
		current_highest_id = 0
		
		Helper.attempt_and_raise(3) {
			page = open("http://eztv.it/").read.to_s
			
			current_highest_id = page.scan(/\/ep\/(\d+)\//).flatten.uniq.collect {
				|id|
				id.to_i
			}.max
			
			if (current_highest_id < 41000)
				raise StandardError.new("Eztv module couldn't get a reference episode ID and was unable to tell which torrents are new.")
			end
		}
		
		result = current_highest_id > 41000 ? current_highest_id.to_s : 41000.to_s
		
		File.open(@@eztv_cache_path, "w") do |f|
			f.write(result)
			puts "Eztv: cache's reference ID set to #{result}"
		end
	end
	
	def self.settings_notice
		"-Type <b><i>true</i></b> in the first line if you want 720p-only downloads (else type <b><i>false</i></b> for non-720p downloads only)
		-Type one show name per line.
		
		<b>Example:</b>
		true
		Breaking Bad
		The Big Bang Theory
		The Walking Dead
		Two and a Half Men"
	end
	
	def self.has_on_demand? # => Boolean
		true
	end
	
	def self.on_demand
		result = []
		
		page = nil
		Helper.attempt_and_raise(3) {
			page = open("http://eztv.it/").read.to_s
		}
		
		items = page.scan(/<tr\sname=\"hover\"\sclass=\"forum_header_border\">(.*?)<\/tr>/im).flatten.uniq
		
		items.each {
			|item|
			
			reference = item.scan(/\/ep\/(\d+)\//im).flatten.uniq.first
			name = item.scan(/class=\"epinfo\">(.*?)<\/a>/im).flatten.uniq.first
			
			result << [name, reference]
			links = item.scan(/<a\shref=\"([^\"]*?)\"\sclass=\"download_\d\"/im).flatten.uniq
		}
		
		result
	end
	
	def self.download_on_demand(reference)
		result = []
		
		page = nil
		Helper.attempt_and_raise(3) {
			page = open("http://eztv.it/").read.to_s
		}
		
		items = page.scan(/<tr\sname=\"hover\"\sclass=\"forum_header_border\">(.*?)<\/tr>/im).flatten.uniq
		
		items.each {
			|item|
			
			ref = item.scan(/\/ep\/(\d+)\//im).flatten.uniq.first
			next if ref != reference
			name = item.scan(/class=\"epinfo\">(.*?)<\/a>/im).flatten.uniq.first
			links = item.scan(/<a\shref=\"([^\"]*?)\"\sclass=\"download_\d\"/im).flatten.uniq
			link = nil
			
			# Get mirror links if the main one is down
			links.each {
				|mirror|
				
				begin
					link = mirror unless open(mirror).nil?
				rescue StandardError => e
				end
				
				break if (!link.nil?)
			}
			
			file = {:download => link, :filename => name+".torrent"}
			result << {:files => [file], :reference => ref} unless link.nil?
		}
		
		result
	end

	def self.broken?
		false
	end
	
	def self.description
		"Downloads US & UK TV shows <b>torrent</b>s from <a href=\"http://eztv.it\">EZTV</a>."
	end
end