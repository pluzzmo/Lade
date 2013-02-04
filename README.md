##Lade 1.0.1

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
`killall ruby`, then delete Lade's folder

#####Changelog
######1.0.1
- Removed host BillionUploads.com (implemented captcha…)
- Added host PutLocker.com
- Switched module 'Shows' to use PutLocker instead
- Added HTTP authentication for Lade's server, see settings
- Some CSS adjustments