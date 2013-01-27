class Template
	# This is a Template Lade module, use it as a starting point for developing your own
	# module.
	#
	# Some methods might not be well explained, so check the official modules for a working
	# example.
	#
	# Note: the class name should only have one capitalized letter (the first one).
	
	def self.run(to_download, already_downloaded, max) # => Array
		##
		# Return an Array of Hashes containing the links to download.
		#
		# Hash structure:
		# {
		# 	# (:type) Type of links; 0 = direct, 10 = for jDownloader
		# 	:type => 0,
		# 	# (:links) Array of String: Download link for each file. (e.g. multiple links if it's a multipart release) (NOT mirrors)
		# 	:links => [link1, link2],
		# 	# (:filenames) Array of String: Name of each file. Same number as :links
		# 	:filenames => [filename1, filename2],
		# 	# (:file) String: Name of the whole release, or name of multipart files without extension
		# 	:file => filename,
		# 	# (:reference) String: reference of this item for later identification. (e.g. torrent id, permalink, etc.)
		# 	:reference => reference
		# }
		#
		#- Use the parameters to identify what the user wants downloaded (to_download),
		#  what was already downloaded (already_downloaded) and the maximum number
		#  of releases to download (max).
		#
		# => Parameters:
		#    - to_download (ListFile [see helper.rb]): the settings file that was filled in
		#      the module's settings page
		#    - already_downloaded (Array): references of previous releases downloaded by
		#      this module
		#    - max (Integer): maximum number of releases you can download
		##
				
		##
		# EXAMPLE
		##
		
		result = []
		remaining = max
		
		items = [] # fetch a list of what's available on the website
		
		items.each {
			|release_name, reference, link, filename|
			
			should_download = to_download.include?(release_name)
			old_release = already_downloaded.include?(reference)
			
			if (should_download && !old_release)
				result << {:type => 0,
					:links => [link],
					:filenames => [filename],
					:file => filename,
					:reference => reference }

				remaining = remaining - 1
			end

			break if remaining < 1
		}
		
		result
	end	

	def self.always_run # => none
		##
		# Called each time, even if Lade is disabled
		##
	end
	
	def self.update_cache # => none
		##
		# Called when run(a,b,c) returns an empty array.
		##
	end
	
	def self.settings_notice # => String
		##
		# Return a String to be directly shown in the settings page of your module
		#
		#- You can add Javascript/JQuery to make it easier for users to fill the textarea.
		#- There's already a Javascript helper function "add(x)" that adds x to the textarea.
		#  To be used this way: <a onclick="add('name');">name</a>
		##
		
		"Change this String in the 'settings_notice' method."
	end
	
	def self.has_on_demand? # => Boolean
		##
		# Return a Boolean indicating whether this module should be available in the 'on demand' section
		#
		#- Only return true if the methods 'on_demand', 'download_on_demand(reference)' have been implemented.
		##
		
		true
	end
	
	def self.on_demand # => Array
		##
		# Return an Array of Arrays containing the names and references of the items available for download.
		# Names & References are both Strings.
		#
		#- The Array of Arrays should be organized this way: [[name1, reference1], [name2, reference2], ...]
		#- The references are used to identify the user's selection to later start the download.
		##
		
		[]
	end
	
	def self.download_on_demand(reference) # => Array
		##
		# Return an Array of Hashes containing the links to download.
		#
		# Hash structure:
		# {
		# 	# (:type) Type of links; 0 = direct, 10 = for jDownloader
		# 	:type => 0,
		# 	# (:links) Array of String: Download link for each file. (e.g. multiple links if it's a multipart release) (NOT mirrors)
		# 	:links => [link1, link2],
		# 	# (:filenames) Array of String: Name of each file. Same number as :links
		# 	:filenames => [filename1, filename2],
		# 	# (:file) String: Name of the whole release, or name of multipart files without extension
		# 	:file => filename,
		# 	# (:reference) String: reference of this item for later identification. (e.g. torrent id, permalink, etc.)
		# 	:reference => reference
		# }
		#
		#- Use the reference String to identify what the user wants to download,
		#  get the links and other info and return them.
		##
		
		[]
	end
	
	def self.download_on_demand_step2(reference) # => Array
		##
		# This is only used in case multi-step on demand (you probably won't need it).
		# See the official module 'Shows' for an example.
		# Also see "get '/ondemand/:module/*' do" in server.rb to learn how it works.
		##
	end

	def self.broken? # => Boolean
		##
		# Return a Boolean indicating whether this module is currently broken or not.
		#
		#- If this method returns true, the user will be notified in the home page of Lade
		#  and the server won't try to use the module to download releases.
		#- A good idea would be for the developer to put a file on his webserver
		#  telling the module if it's up to date or needs a fix.
		##
		
		false
	end
	
	def self.description # => String
		"<b>DEVELOPERS ONLY.</b> Use it as a starting point for developing your own module."
	end
end