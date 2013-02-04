path = File.join(File.dirname(__FILE__), *%w[/])
load path+"updater.rb"

if (ARGV[0] == "start")
	Updater.start
elsif (ARGV[0] == "stop")
	Updater.quit
elsif (ARGV[0] == "restart")
	Updater.restart
elsif (ARGV[0] == "forcestart")
	Updater.forcestart
end