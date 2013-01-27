class Nyaa
	# a file containing a torrent ID. any torrent ID found lesser than this reference ID would be ignored
  @@nyaa_cache_path = File.join(File.dirname(__FILE__), *%w[../cache/nyaa])
  @@base_search_url = "http://www.nyaa.eu/?page=search&cats=0_0&filter=0&term="
  
  def self.run(to_download, already_downloaded, max)
	  result = []
	  remaining = max
		
		cache_id = 0
		File.open(@@nyaa_cache_path, "r") do |f|
			cache_id = f.read.strip.to_i
		end
		
		raise StandardError.new("Nyaa module couldn't get a reference torrent ID and was unable to tell which torrents are new.") if cache_id == 0
		
		to_download.list.each {
			|query|
			
			puts "Trying search query '#{query}'..."
			search_result = open(@@base_search_url+CGI.escape(query)).read.to_s
			
			torrent_ids = search_result.scan(/torrentinfo\&#38;tid\=(\d+)\"\>(.*?)\<\//im).uniq.collect {
	  		|id, name|
	  		[id.to_i, name] if (id.to_i > cache_id && !already_downloaded.include?(id))
	  	}.compact.sort {
		  	|a, b|
		  	b.first <=> a.first
	  	}
	  	
	  	torrent_ids.each {
		  	|id, name|
		  	
		  	break if remaining < 1
		  	result << {:type => 0,
			  	:links => ["http://www.nyaa.eu/?page=download&tid="+(id.to_s)],
			  	:filenames => [name+".torrent"],
			  	:file => name+".torrent",
			  	:reference => id.to_s
		  	}
		  	
		  	remaining = remaining - 1
	  	}
	  	
	  	break if remaining < 1
		}
		
		return result
  end
  
  def self.install
		Nyaa.update_cache
	end
	
	def self.always_run
		if (!File.exist?(@@nyaa_cache_path))
			Nyaa.update_cache
		end
	end
	
	def self.update_cache
		page = open("http://www.nyaa.eu/").read.to_s
			
		current_highest_id = page.scan(/tid\=(\d+)\"/).flatten.uniq.collect {
			|id|
			id.to_i
		}.sort.last
		
		File.open(@@nyaa_cache_path, "w") do |f|
			f.write(current_highest_id.to_s)
		end
	end
	
	def self.has_on_demand?
		false
	end
	
	def self.settings_notice
		"Type one <b>search query</b> per line.
		
		Make sure your queries are specific enough so that this module doesn't download torrents you might not need.
		
		Visit <a href=\"http://nyaa.eu\">Nyaa.eu</a> and use the search feature to determine the search words that fit your needs.
		
		<b>Example:</b>
		HorribleSubs Hunter X Hunter 720p
		Commie Tamako Market
		rori Sakurasou"
	end

	def self.description
		"Searches <a href=\"http://nyaa.eu\">Nyaa.eu</a> using given search terms and downloads the resulting torrents. (mostly Anime)"
	end
	
	def self.broken?
		false
	end
	
	def self.update_url
		nil
	end
end