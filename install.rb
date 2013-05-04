require 'open-uri'

def exit_if_unsatisfying(args)
	if (!system(*args))
		status = $?
		if (!status.termsig.nil?)
			if (status.termsig == 2)
				puts "User stopped install."
			else
				puts "Install stopped with signal #{status.termsig}"
			end
		else
			puts "Error executing \`#{args.join(' ')}\`, install can't proceed."
		end

		puts "You can safely remove Lade's folder."
		exit
	end
end

begin
	wget_installed = !(`which wget`.empty?)
	if !wget_installed
		puts "Wget is not installed. Lade requires wget, please install it then try again."
		exit
	end

	pwd = Dir.pwd
	Dir.mkdir("Lade")
	Dir.chdir("Lade")

	puts "*Lade will be installed to '#{Dir.pwd}'"
	available_rev = "master"
	begin
		available_rev = open("https://raw.github.com/inket/Lade/master/rev").read.to_s.gsub(/\s/m, "")
	rescue StandardError
	end

	File.open("updater.rb", "w") do |f|
		file = (open "https://raw.github.com/inket/Lade/#{available_rev}/updater.rb").read.to_s
		f.write(file)
	end

	puts "Downloading Lade..."
	exit_if_unsatisfying(["ruby", "updater.rb", "--update"])

	bundler_installed = !(`which bundle`.empty?)
	if !bundler_installed
		puts "Installing bundler... (you might need to enter your password)"
		exit_if_unsatisfying(["sudo", "gem", "install", "bundler"])
	end

	puts "Checking for dependencies..."
	exit_if_unsatisfying(["bundle", "install"])

	puts "Starting Lade..."
	exit_if_unsatisfying(["ruby", "process.rb", "start"])

	puts "----------------------------------------------------"
	puts "Lade started! Visit http://localhost:3333/ on your browser."
	puts "Type 'ruby process.rb start' in Terminal to start Lade next time!"
	`sleep 2 && open "http://localhost:3333/"`

	File.delete(pwd+"/"+__FILE__)
rescue Interrupt
	exit
end