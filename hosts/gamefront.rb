require 'open-uri'
require 'net/http'

class GameFront
	@@user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/536.26.17 (KHTML, like Gecko) Version/6.0.2 Safari/536.26.17"
	
	def self.check_urls(urls)
		files = []

		urls.each {
			|url|

			next if url.match(/(?:www\.)?gamefront\.com\/files\/\d{8}/im).nil?

			files << self.check_file(url)
		}

		self.organize(files.compact)
	end

	def self.check_file(url)
		valid = nil
		
		Helper.attempt(2) {
			valid = catch(:valid) {
				page, cookie = nil
				
				id = url.scan(/\/files\/(\d{8})/im).flatten.first
				throw(:valid) if id.nil?
				
				Helper.attempt_and_raise(3) {
					http = Net::HTTP.new("www.gamefront.com")
					req = Net::HTTP::Get.new("/files/#{id}")
					req["User-Agent"] = @@user_agent
					resp = http.request(req)
					page = resp.body
					cookie = resp["set-cookie"]
					throw(:valid) if (resp.code.to_i != 200)
				}
	
				filename = page.scan(/<dt>File Name:<\/dt>\s*<dd>(?:<span\stitle=\")?(.*?)(?:\".*?)?<\/dd>/im).flatten.first
				throw(:valid) if id.nil?
				
				size = page.scan(/<dt>File Size:<\/dt>\s*<dd>(.*?)<\/dd>/im).flatten.first
				throw(:valid) if id.nil?
				
				noextension = filename.gsub(/#{"\\"+File.extname(filename)}$/, "")
				if noextension.match(/\.part\d+$/)
					noextension = noextension.gsub(/#{"\\"+File.extname(noextension)}$/, "")
				end
				
				{
					:url => url,
					:id => id,
					:cookie => cookie,
					:filename => filename,
					:noextension => noextension,
					:size => Helper.to_bytes(size)
				}
			}
			
			raise StandardError.new("Dead link? Trying again to make sure...") if valid.nil?
		}
		
		puts "#{url} - Dead link" if valid.nil?
		nil || valid
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

		# calculate total size for each group, mark incomplete groups as :dead
		grouped_files.each {
			|group|
			group[:size] = 0
			last_part = group[:files].first[:filename].scan(/\.part(\d+)\.rar/).flatten.first.to_i
			
			group[:files].each {
				|file|

				group[:size] += file[:size].to_i
				
				part_num = file[:filename].scan(/\.part(\d+)\.rar/).flatten.first.to_i
				last_part = part_num if part_num > last_part
			}
			
			if (last_part > group[:files].count)
				group[:dead] = true
				group[:files].each {
					|file|
					file[:dead] = true
				}
			end
		}
		
		grouped_files
	end

	def self.get_download_link(file)
		return nil if (file.nil? || file[:dead])
		
		directlink = nil
		
		Helper.attempt(3) {
			http = Net::HTTP.new("www.gamefront.com")
			req = Net::HTTP::Get.new("/files/service/thankyou?id=#{file[:id]}")
			req["User-Agent"] = @@user_agent
			req["Referer"] = "http://www.gamefront.com/files/#{file[:id]}"
			req["Cookie"] = file[:cookie]
			response = http.request(req)

			directlink = response.body.scan(/downloadUrl.*?$/i).flatten.first.scan(/\'(.*?)\'/i).flatten.first
			
			raise StandardError.new("Error while getting the direct link...") if directlink.nil?
		}
		
		(directlink.nil? || directlink.empty?) ? nil : directlink
	end
end