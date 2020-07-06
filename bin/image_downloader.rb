#!/usr/bin/env ruby

require 'date'
require 'fileutils'
require 'optimist'
require_relative '../scripts/target'

opts = Optimist.options do
  opt :build_date,  "Build date(s) to download image for, in YYYYMMDD format. Defaults to yesterday", :type => :strings
  opt :build_type,  "Buid type, nightly or release", :type => :string, :default => "nightly"
  opt :fileshare  , "Fileshare path", :type => :string, :default => "/build/fileshare/"
  opt :only,        "Image(s) to download", :type => :strings, :default => Build::Target.default_types
  opt :reference,   "Git reference (e.g. jansa, jansa-1)",  :type => :string, :required => true
end

build_dates      = opts[:build_date] || (Date.today - 1).strftime("%Y%m%d")
destination_root = "#{opts[:fileshare]}/#{opts[:reference].split("-").first}"

targets = opts[:only].collect { |only| Build::Target.new(only) }

build_dates.each do |build_date|
  if opts[:build_type] == "release"
    build_ref = opts[:reference]
    build_dir = "#{build_date}-#{build_ref}"
    symlink_names = ["stable", opts[:reference]]
  else
    build_ref = "#{opts[:reference]}-#{build_date}"
    build_dir = build_date
    symlink_names = ["latest"]
  end
  destination = "#{destination_root}/#{build_dir}"

  FileUtils.mkdir_p(destination)
  Dir.chdir(destination) do
    targets.each do |image|
      file_name = "manageiq-#{image}-#{build_ref}.#{image.file_extension}"
      source_path = "http://releases.manageiq.org/#{file_name}"

      if system("wget --spider #{source_path}")
        puts "Downloading #{source_path}"
        if system("wget -O #{file_name} #{source_path}")
          puts "Download completed"
        else
          puts "Failed to download the image"
        end
      else
        puts "xxx #{source_path} doesn't exist xxx"
      end
    end

    if Dir.empty?(destination)
      puts "No image was created for #{build_date}"
      FileUtils.rm_rf(destination)
    else
      system("/usr/bin/sha256sum * > SHA256SUM")
      system("/usr/bin/gpg --batch --no-tty --passphrase-file /root/.gnupg/pass --pinentry-mode loopback -b SHA256SUM")
      FileUtils.cp("/root/.gnupg/manageiq_public.key", ".")

      symlink_names.each do |name|
        puts "Creating symlinks"
        FileUtils.rm_f("#{destination_root}/#{name}", :verbose => true)
        FileUtils.ln_s(destination, "#{destination_root}/#{name}", :verbose => true)
      end
    end
  end
end
