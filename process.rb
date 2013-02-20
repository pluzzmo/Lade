path = File.join(File.dirname(__FILE__), *%w[/])
load path+"updater.rb"

if (ARGV[0] == "start")
	Updater.install_needed_gems
	Updater.start
elsif (ARGV[0] == "stop")
	Updater.quit
elsif (ARGV[0] == "restart")
	Updater.install_needed_gems
	Updater.restart
elsif (ARGV[0] == "forcestart")
	Updater.install_needed_gems
	Updater.forcestart
end