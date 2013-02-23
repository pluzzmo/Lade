require 'open-uri'

class Rapidshare
	@@api_url = "https://api.rapidshare.com/cgi-bin/rsapi.cgi?sub="
	
	def self.check_urls(urls)
		ids = []
		filenames = []
		urls.each {
			|url|
			
			next if url.match(/https?\:\/\/(?:www\.)?rapidshare\.com\/files\/\d+?\/.*?/).nil?
			
			t = url.split("files/")[1].split("/")
			ids << t[0]
			filenames << t[1]
		}
		
		check_files(ids, filenames)
	end
	
	def self.check_files(ids, filenames)
		raise StandardError.new("Rapidshare: IDs and filenames do not correspond.") unless ids.count == filenames.count
		raise StandardError.new("Rapidshare: No IDs given.") if ids.empty?
		
		request_url = @@api_url+"checkfiles&files="+ids.join(",")+"&filenames="+filenames.join(",")
		
		files = []
		(open request_url).read.to_s.lines {
			|line|
			
			fields = line.split(",")
			noextension = fields[1].split(".").take(fields[1].split(".").count-1).join(".")
			if noextension.match(/part\d+$/)
				noextension = noextension.split(".").take(noextension.split(".").count-1).join(".")
			end
			
			files << {
				:id => fields[0].strip,
				:filename => fields[1].strip,
				:noextension => noextension.strip,
				:size => fields[2].strip,
				:server => fields[3].strip,
				:status => fields[4].strip,
				:shorthost => fields[5].strip,
				:md5 => fields[6].strip,
				:download => @@api_url.gsub("/api", "/rs"+fields[3]+fields[5])+"download&fileid="+fields[0]+"&filename="+fields[1]
			}
		}
		
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
		
		# mark dead links
		grouped_files.each {
			|group|
			group[:dead] = false
			group[:size] = 0
			
			group[:files].each {
				|file|
				
				group[:size] += file[:size].to_i
				group[:dead] = true unless file[:status] == "1"
			}
		}
		
		grouped_files
	end
end