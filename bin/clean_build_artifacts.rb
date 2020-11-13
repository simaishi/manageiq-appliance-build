#!/usr/bin/env ruby

require 'date'
require 'fileutils'
require 'optimist'

opts = Optimist.options do
  opt :artifacts_dir,   "Artifacts root directory",          :default => "/build/fileshare"
  opt :latest_inactive, "Latest inactive branch",            :default => "ivanchuk"
  opt :retention_days,  "Number of days to keep builds for", :default => 28
  opt :skip,            "Directories to skip",               :default => ["test"]
  opt :dry_run,         "Execute without making changes",    :default => true
end

dry_run = opts[:dry_run]

def valid_build_dir_format(build)
  # If directory name starts with 8 digits, assume it's YYYYMMDD, which is our build directory format
  File.basename(build).match?(/^[0-9]{8}/)
end

def find_tag_builds(branch)
  # tab builds are symlinks, find both symlink and its source
  Dir.glob("#{branch}-*")
    .map { |build| [build, File.basename(File.realpath(build))] }
    .flatten
    .sort
end

def all_builds
  Dir.glob("*").select { |build| valid_build_dir_format(build) }
end

def run(dry_run, builds_to_delete)
  if dry_run
    puts "Builds to delete:\n#{(builds_to_delete - ["latest"]).join(" ")}\n\n"
  else
    #FileUtils.rm_r(builds_to_delete, verbose: true)
  end
end

Dir.chdir(opts[:artifacts_dir]) do
  valid_branches    = Dir.glob("*").sort - ["master"] - opts[:skip]
  active_branches   = valid_branches[valid_branches.index(opts[:latest_inactive])+1..-1]
  inactive_branches = valid_branches - active_branches

  ## For 'master' branch ##
  # delete nightly builds before last active branch was created
  puts "***  Deleting old 'master' nightly builds  ***\n\n"
  latest_branch_first_build =  File.basename(Dir.glob("#{active_branches.last}/*")
	                         .select { |build| valid_build_dir_format(build) }
	                         .sort
	                         .first)
  Dir.chdir("master") do
    builds_to_delete = all_builds.select { |build| build < latest_branch_first_build }
    run(dry_run, builds_to_delete)
  end

  ## For active branches ##
  # delete nightly builds older than any tagged build or 4 weeks (whichever is less destructive)
  active_branches.each do |branch|
    puts "***  Deleting old '#{branch}' nightly builds  ***\n\n"
    Dir.chdir(branch) do
      tag_builds         = find_tag_builds(branch)
      last_tag_build     = tag_builds.select { |build| valid_build_dir_format(build) }.last
      all_nightly_builds = all_builds - tag_builds
      first_build_after_retention = (Date.today - opts[:retention_days]).strftime("%Y%m%d")

      # if last tag < 4 weeks old, delete > 4 weeks build
      # if last tag > 4 weeks old, delete all prior builds
      if last_tag_build.nil? || ( last_tag_build > first_build_after_retention )
        builds_to_delete = all_nightly_builds.select { |build| build < first_build_after_retention }
      else
        builds_to_delete = all_nightly_builds.select { |build| build < last_tag_build }
      end

      run(dry_run, builds_to_delete)
    end
  end

  ## For inactive branches ##
  # delete all nightly builds and just keep 'tag' builds
  inactive_branches.each do |branch|
    puts "***  Deleting all '#{branch}' nightly builds  ***\n\n"
    Dir.chdir(branch) do
      tag_builds = find_tag_builds(branch)
      builds_to_delete = all_builds - tag_builds - ["stable"]

      run(dry_run, builds_to_delete)
      #FileUtils.ln_s("stable", "latest") unless opts[:dry_run]
    end
  end
end
