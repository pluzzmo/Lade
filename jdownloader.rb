require 'open-uri'
require 'cgi'

class JDownloader
  attr_accessor :remotecontrol_url, :nightly
   
  def initialize(remotecontrol_url)
	  begin
		  remotecontrol_url = "http://"+remotecontrol_url unless remotecontrol_url.start_with?("http://")
    	rcversion = open(remotecontrol_url+"/get/rcversion").read.to_s
    	
    	@remotecontrol_url = remotecontrol_url
    	@nightly = (rcversion.to_i >= 12612)
    rescue Exception => e
	    puts e.to_s
	    puts "There was a problem communicating with JDownloader"
	    raise
	  end
  end
  
  def enclose_request(uri)
	  begin
		  return open(@remotecontrol_url+uri).read.to_s
		rescue Exception => e
			puts e.to_s
			puts "There was a problem communicating with JDownloader"
			raise
		end
	end
	
	def change_download_dir(package_name, download_dir)
		changed = false
		slept = 0
		
		valid_download_dir = download_dir.gsub("/", "%2F")
		request_uri = "/action/grabber/set/downloaddir/"+CGI.escape(package_name)+"/"+valid_download_dir
		
		result = enclose_request(request_uri)
		changed = !result.downcase.start_with?("error")
		
		while !changed && slept < 10
			sleep 1
			slept += 1
			result = enclose_request(request_uri)
			changed = !result.downcase.start_with?("error")
		end
		
		return changed
	end
	
	def get_package_names
		uri = "/get/grabber/list"
		xml_list = enclose_request(uri)
		
		package_names = []
		
		xml_list.scan(/\<packages.*?package_name\=\"(.*?)\".*?\>(.*?)\<\/packages\>/im) {
			|package|
			
			package_names << package[0]
		}
		
		package_names
	end
	
	def old_add_link(link)
		uri = "/action/add/links/grabber0/start1/"+CGI.escape(link).gsub("%3A%2F%2F", "://")
		enclose_request(uri)
	end
	
	def add_links(links)
		parameter = links.collect {
			|link|
			link+"#lade" # marking Lade's links for easier recognition
		}.join("\n")
		
		parameter = CGI.escape(parameter)
		
		uri = "/action/add/links/"+parameter
		enclose_request(uri)
	end
	
	def confirm(package_names)
		escaped_package_names = package_names.collect {
			|p_name|
			Helper.escape_url(p_name)
		}
		uri = "/action/grabber/confirm/"+escaped_package_names.join("/")
		enclose_request(uri)
	end
	
	def prepare
		enclose_request("/set/grabber/autoadding/false")
		enclose_request("/set/grabber/startafteradding/true")
	end
	
	def block_until_grabber_ready(max_seconds = 30)
		slept = 0
		isbusy = true
		
		while (isbusy = eval(enclose_request("/get/grabber/isbusy"))) && slept < max_seconds
			sleep 1
			slept += 1
		end
		
		raise StandardError("JDownloader couldn't verify links. Giving up.") if isbusy
	end
	
	def start_downloads
		enclose_request("/action/start")
	end
	
	def process(links, download_dir)
		begin
			if (@nightly)
				prepare
				
				add_links(links)

				sleep 5
				
				block_until_grabber_ready
				
				package_names = get_package_names
				
				if !package_names.empty?
					package_names.each {
						|package_name|
						change_download_dir(package_name, download_dir)
					}
					
					confirm(package_names)
					
					sleep 1
					
					puts start_downloads+" - "+package_names.to_s
				else
					puts "Couldn't find the added links in JDownloader's grabber. Weird bug ?"
				end
			else
				puts "* Please switch JDownloader's branch to NIGHTLY for better support"
				
				links.each {
					|link|
					old_add_link(link)
					sleep 0.5
				}
			end
		rescue Exception => e
			puts e.to_s
			puts "Error while adding links."
		end
	end
end