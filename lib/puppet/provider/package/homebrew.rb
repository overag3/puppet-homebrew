require 'puppet/provider/package'
require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:package).provide(:homebrew, :parent => Puppet::Provider::Package) do
  desc 'Package management using HomeBrew (+ casks!) on OSX'

  confine :operatingsystem => :darwin

  extend PuppetX::Homebrew::BrewCommand

  has_feature :installable
  has_feature :uninstallable
  has_feature :upgradeable
  has_feature :versionable
  has_feature :install_options

  @brewbin = detect_brew_bin
  commands :brew => @brewbin
  commands :stat => '/usr/bin/stat'

  def run_brew(*args, **opts)
    self.class.run_brew(*args, **opts)
  end

  def fix_checksum(files)
    begin
      for file in files
        File.delete(file)
      end
    rescue Errno::ENOENT
      Puppet.warning "Could not remove mismatched checksum files #{files}"
    end

    raise Puppet::ExecutionFailure, "Checksum error for package #{name} in files #{files}"
  end

  def resource_name
    if @resource[:name].match(/^https?:\/\//)
      @resource[:name]
    else
      @resource[:name].downcase
    end
  end

  def install_name
    should = @resource[:ensure].downcase

    case should
    when true, false, Symbol
      resource_name
    else
      "#{resource_name}@#{should}"
    end
  end

  def install_options
    Array(resource[:install_options]).flatten.compact
  end

  def self.instances
    package_list.collect { |hash| new(hash) }
  end

  def latest
    begin
      Puppet.debug "Querying latest for #{resource_name} package..."
      output = run_brew('info', resource_name)

      output.each_line do |line|
        line.chomp!
        next if line.empty?
        next if line !~ /#{@resource[:name]}:\s(.*)/i
        Puppet.debug "  Latest versions for #{resource_name}: #{$1}"
        versions = $1
        return $1 if versions =~ /stable (\d+[^\s]*)\s+\(bottled\)/
        return $1 if versions =~ /stable (\d+.*), HEAD/
        return $1 if versions =~ /stable (\d+.*)/
        return $1 if versions =~ /(\d+.*)\s+\(auto_updates\)/
        return $1 if versions =~ /(\d+.*)/
      end
      nil
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not query latest version of package: #{detail}"
    end
  end

  def query
    self.class.package_list(:justme => resource_name)
  end

  def install
    begin
      Puppet.debug "Package #{install_name} found, installing..."
      output = run_brew('install', install_name, *install_options)

      if output =~ /sha256 checksum/
        Puppet.debug "Fixing checksum error..."
        mismatched = output.match(/Already downloaded: (.*)/).captures
        fix_checksum(mismatched)
      end
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not install package: #{detail}"
    end
  end

  def uninstall
    begin
      Puppet.debug "Uninstalling #{resource_name}"
      run_brew('uninstall', resource_name)
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not uninstall package: #{detail}"
    end
  end

  def update
    if installed?
      begin
        Puppet.debug "Package #{resource_name} found, upgrading..."
        output = run_brew('upgrade', install_name, *install_options)

        if output =~ /sha256 checksum/
          Puppet.debug "Fixing checksum error..."
          mismatched = output.match(/Already downloaded: (.*)/).captures
          fix_checksum(mismatched)
        end
      rescue Puppet::ExecutionFailure => detail
        raise Puppet::Error, "Could not upgrade package: #{detail}"
      end
    else
      install
    end
  end

  def installed?
    begin
      Puppet.debug "Check if #{resource_name} package installed"
      is_not_installed = run_brew('info', install_name).split("\n").grep(/^Not installed$/).first
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not get status of package: #{detail}"
    end
    is_not_installed.nil?
  end

  def self.package_list(options={})
    Puppet.debug "Listing installed packages"
    begin
      if resource_name = options[:justme]
        escaped = Regexp.escape(resource_name)
        # Targeted single-package lookup: one brew call instead of two full lists.
        # brew list --versions <name> handles both formulae and casks.
        result = run_brew('list', '--versions', resource_name)
        if result.empty?
          Puppet.debug "Package #{resource_name} not installed"
        else
          Puppet.debug "Found package #{resource_name}"
          result = result.lines.grep(/^#{escaped} /).first.to_s
          Puppet.debug "Stored #{result} in package_list"
        end
      else
        result = run_brew('list', '--versions', '--cask')
        result += run_brew('list', '--versions', '--formulae')
      end

      list = result.lines.map { |line| name_version_split(line) }
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list packages: #{detail}"
    end

    if options[:justme]
      return list.shift
    else
      return list
    end
  end

  def self.name_version_split(line)
    if line =~ (/^(\S+)\s+(.+)/)
      {
        :name     => $1,
        :ensure   => $2,
        :provider => :homebrew
      }
    else
      Puppet.warning "Could not match #{line}"
      nil
    end
  end
end
