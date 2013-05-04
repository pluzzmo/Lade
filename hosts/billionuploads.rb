require 'open-uri'
require 'net/http'

class BillionUploads
	
	def self.check_urls(urls)
		files = []

		urls.each {
			|url|
			
			next if url.nil? || url.match(/http\:\/\/(?:www\.)?billionuploads\.com\/[a-z\d]{12}/im).nil?
			
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
			:url => url,
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
			group[:host] = "BillionUploads"
			group[:size] = 0
			
			group[:files].each {
				|file|
				
				group[:size] += file[:size].to_i
			}

			group[:name] = group[:files].first[:filename] if group[:files].count == 1
		}

		grouped_files
	end
	
	def self.get_download_link(file)
		return nil if file.nil?
		
		directlink = nil
		tried_new_session = false
		
		Helper.attempt(2) {
			Helper.attempt(3) {
				result = Net::HTTP.post_form(URI("http://billionuploads.com/"+file[:id]),
				{"id" => file[:id], "rand" => file[:rand], "op" => "download2"})
				
				body = result.body
				link_result = body.scan(/\<a\shref\=\"(.*?)\"\sid\=\"_tlink\"/).flatten.uniq
				
				if link_result.empty?
					puts "File unavailable or expired session..."
					raise StandardError.new("File unavailable or expired session...") 
				end
				
				directlink = link_result.first
			}
			
			if (directlink.nil? && !tried_new_session)
				tried_new_session = true
				
				puts "Generating a new download session..."
				file = self.check_file(file[:url])
				sleep 3
				
				raise StandardError.new("Generating a new download session...")
			end
		}

		
		directlink
	end
end