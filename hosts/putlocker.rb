require 'open-uri'
require 'net/http'

class PutLocker
	def self.check_urls(urls)
		files = []

		urls.each {
			|url|

			next if url.match(/http\:\/\/(?:www\.)?putlocker\.com\/file\/[a-z\d]{16}/im).nil?

			files << self.check_file(url)
		}

		self.organize(files.compact)
	end

	def self.check_file(url)
		page, dead = nil
		
		Helper.attempt(3) {
			resp = Net::HTTP.get_response(URI(url))
			page = resp.body
			dead = (resp.code.to_i != 200)
		}
		
		if (!dead)
			id = url.split("/").last
			hash = page.scan(/value\=\"(.*?)\"\sname\=\"hash\"\>/im).flatten[0]
			filename, size = page.scan(/<h1>(.*?)<strong>\(\s*(.*?)\s*\)<\/strong><\/h1>/im).flatten

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
			:hash => hash,
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

	def self.get_download_link(file, last_time = false)
		return nil if file.nil?
		
		directlink = nil
		
		Helper.attempt(3) {
			full_url = "http://www.putlocker.com/file/"+file[:id]
			
			http = Net::HTTP.new("www.putlocker.com", 80)
			data = "hash=#{file[:hash]}&confirm=Continue as Free User"
			result = http.send_request('POST', "/file/"+file[:id], data, nil)
			
			almost_directlink = result.body.scan(/<a href=\"(\/get_file.*?)\">Download File<\/a>/im).flatten.first
			
			if (!almost_directlink.start_with?("/get_file.php?"))
				raise StandardError.new("Error while getting the direct link, script needs update ?")
			end
			
			res = http.send_request('GET', almost_directlink, nil, nil)
			directlink = res["location"]
		}
		
		if ((directlink.nil? || directlink.empty?) && !last_time)
			puts "Trying again from start..."
			directlink = self.get_download_link(self.check_file(full_url), yes)
		else ((directlink.nil? || directlink.empty?) && last_time)
			puts "Couldn't get direct link... skipping."
		end
		
		(directlink.nil? || directlink.empty?) ? nil : directlink
	end
end