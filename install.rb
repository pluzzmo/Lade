require 'open-uri'

wget_installed = !(`which wget`.empty?)
if !wget_installed
	puts "Wget is not installed. Lade requires wget, please install it then try again."
	exit
end

pwd = Dir.pwd
Dir.mkdir("Lade")
Dir.chdir("Lade")

puts "Installing Lade to #{Dir.pwd}"
File.open("updater.rb", "w") do |f|
	file = (open "https://dl.dropbox.com/u/2439981/Lade/updater.rb").read.to_s
	f.write(file)
end

puts "Downloading Lade..."
system("ruby", "updater.rb", "-f")

bundler_installed = !(`which bundle`.empty?)
if !bundler_installed
	puts "Installing bundler... (you might need to enter your password)"
	system("sudo", "gem", "install", "bundler")
end

puts "Checking for dependencies..."
system("bundle", "install")

system("ruby", "process.rb", "start")

puts "----------------------------------------------------"
puts "Lade started! Visit http://localhost:3333/ on your browser."
puts "Type 'ruby process.rb start' in Terminal to start Lade next time!"
`sleep 2 && open "http://localhost:3333/"`

File.delete(pwd+"/"+__FILE__)