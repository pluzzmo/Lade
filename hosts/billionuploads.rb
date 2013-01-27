require 'open-uri'
require 'net/http'

class BillionUploads
	
	def self.check_urls(urls)
		files = []

		urls.each {
			|url|
			
			next if url.match(/http\:\/\/(?:www\.)?billionuploads\.com\/[a-z\d]{12}/im).nil?
			
			files << self.check_file(url)
		}
		
		self.organize(files.compact)
	end
	
	def self.check_file(url)
		page = (open url).read.to_s

		dead = page.scan(/\<b\>File not found\<\/b\>/im).flatten
		
		if (dead.empty?)
			id = page.scan(/name\=\"id\"\svalue\=\"(.*?)\"\>/im).flatten[0]
			rand = page.scan(/name\=\"rand\"\svalue\=\"(.*?)\"\>/im).flatten[0]
			filename = page.scan(/\<b\>Filename:\<\/b\>(.*?)\<br\>/im).flatten[0]
			size = page.scan(/\<b\>Size:\<\/b\>(.*?)\<br\>/im).flatten[0]
			
			noextension = filename.split(".").take(filename.split(".").count-1).join(".")
			if noextension.match(/part\d+$/)
				noextension = noextension.split(".").take(noextension.split(".").count-1).join(".")
			end
		else
			puts "#{url} - Dead link"
			return nil
		end
		
		{
			:id => id,
			:rand => rand,
			:filename => filename,
			:noextension => noextension,
			:size => Helper.to_bytes(size)
		}
	end
	
	def self.organize(files)
		# detect multipart files and organize them in groups
		grouped_files = []
		files.each {
			|file|
			
			added = false
			
			grouped_files.each {
				|group|
				if group[:name] == file[:noextension]
					group[:files] << file
					added = true
					break
				end
			}
			
			next if added
			
			grouped_files << {:name => file[:noextension], :files => [file]}
		}
		
		grouped_files.each {
			|group|
			group[:size] = 0
			
			group[:files].each {
				|file|
				
				group[:size] += file[:size].to_i
			}
		}
	end
	
	def self.get_download_link(file)
		return nil if file.nil?
		unavailable = true
		tries = 0
		
		while (unavailable && tries < 5)
			tries += 1
			sleep 1
			
			result = Net::HTTP.post_form(URI("http://billionuploads.com/"+file[:id]),
			{"id" => file[:id], "rand" => file[:rand], "op" => "download2"})
			
			html = result.body
			directlink = html.scan(/\<a\shref\=\"(.*?)\"\sid\=\"_tlink\"/).flatten.uniq
			
			if directlink.empty?
				puts "File must be unavailable... #{"trying again..." if (tries < 5)}"

				if tries == 5
					puts "Generating a new download session..."
					directlink = self.get_download_link(self.check_file("http://billionuploads.com/"+file[:id]))					
					
					unavailable = false unless directlink.nil?
					directlink = [directlink]
				end
			else
				unavailable = false
			end
		end
		
		directlink[0] unless unavailable
	end
end