##Lade 1.2

#####Description

Lade downloads your favorite shows, anime, etc. automatically.<br>Just set it up and forget about it.


#####Requirements
1. OS X or Linux
2. wget (`brew install wget` / `sudo apt-get install wget`)
3. unrar (`brew install unrar` / `sudo apt-get install unrar`)

Lade will get the rest automatically.

#####Install

Navigate to where you want Lade's folder created, then

`wget "https://dl.dropbox.com/u/2439981/Lade/install.rb" && ruby install.rb`

#####Uninstall
`ruby process.rb stop`, then delete Lade's folder

#####Changelog
######1.2
- Changed "on demand" pages/modules mechanism to allow for threading. Much **less waiting**, much less network usage, much less prone to errors.
- Added **Download History** so you can restart downloads if need be
- New module: **Movies**! Downloads torrents of high quality movies from PublicHD
- **ListSources**: You can now load lists from various sources such as IMDB, RottenTomatoes, Pogdesign, Animecalendar, so you don't have to type shows or movie names by hand in module settings.
- Lade now requires the gem `json`. Launch Lade through Terminal to install it if you don't have it already.
- Lade will now indicate when it's looking for new releases on its homepage.
- JS clean-up on lots of pages
- Tiny fixes to hosts
- Updated jQuery

Notable module updates:

- Slow modules (those that require a lot of network requests) are now threaded
- *Anime* will now rely on episode numbers too, so that it doesn't download the same episode in two different releases.


Module developers:

- This version changes a lot of things (especially the "on demand" mechanism). Use the official modules as reference and you'll be alright. Template module is not up to date for the moment.

Known issues:

- EventSource is not supported in Internet Explorer, I'll have to find a fallback. In the meantime, don't expect "on demand" pages to work on IE.

######1.1.3
- Rewrote module Shows to use a new and much better source with PutLocker+BillionUploads+GameFront links
- Brought back BillionUploads support
- Fixed Lade trying to extract archives that are already being extracted
- Fixed 'Maximum concurrent downloads' taken into account even if Lade is set to require confirmation for downloads
- Fixed adding items to module settings' textarea sometimes not working

######1.1.2
- Updated Shows module to inform users that it's "broken", it will start working again when MyRLS.me is back to normal (it's been down for a few days now); Use the Eztv module & torrent to get your shows in the meantime.
- Updated Anime module to search folders in download source. Issue #1
- Fixed rare issues with host GameFront

######1.1.1
- Changed the way Lade and modules exchange links. (see Template to understand the new method)
	- Moved huge part of download mechanism to Lade instead of the modules
	- Modules are easier to understand/write as a result
	- Cleaner code
- Updated official modules accordingly

######1.1
- Added Growl notifications! (needs gem *ruby_gntp* + see settings to set it up)
- You can now configure Lade to wait for your confirmation before starting downloads.
- Organized settings page in a major way, check it out!
- Added Feedback link


######1.0.5
- Fixed module 'Nyaa' not stripping html entities from filenames
- Fixed irregularities in how Lade moves finished torrent downloads (Now: won't move folders anymore + will try moving downloads even if the extension is missing from the .torrent name)
- Fixed module 'Shows' not downloading from GameFront if no PutLocker were found
- Fixed Maximum Concurrent Downloads setting not being taking into account because `Lade.concurrent_downloads_count` wasn't working

######1.0.4
- Added GameFront host
- Added GameFront support for module 'Shows' (PutLocker links have more priority, though)

######1.0.3
- Added 'on demand' for module 'Nyaa'
- Added a new module 'Eztv' for [eztv.it](eztv.it)
- Added filtering ability in 'on demand' pages

######1.0.2
- Fixed module 'Nyaa' which sometimes malfunctioned if it couldn't connect to the website
- Fixed a case where downloaded torrents weren't moved back to Lade's downloads folder because the torrent history was cleared
- Added code for starting/restarting/quitting Lade:
	- `ruby process.rb start` to start
	- `ruby process.rb restart` to restart
	- `ruby process.rb stop` to stop/quit
	- `http://<lade_ip>/stop`, `http://<lade_ip>/restart` can also be used on your web browser
- Added a basic api method `http://<lade_ip>/api/downloads/count` that does exactly what you expect it to do. (Use *login:password@<lade_ip>* with authentication enabled)
	
######1.0.1
- Removed host BillionUploads.com (implemented captcha…)
- Added host PutLocker.com
- Switched module 'Shows' to use PutLocker instead
- Added HTTP authentication for Lade's server, see settings
- Updates & Extraction are now enabled by default
- Some CSS adjustments