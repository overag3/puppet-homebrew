require 'json'
require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:homebrew_tap).provide(:brew) do
  desc 'Manages Homebrew taps using the `brew tap` command on macOS.'

  extend PuppetX::Homebrew::BrewCommand

  confine :operatingsystem => :darwin
  defaultfor :operatingsystem => :darwin

  @brewbin = detect_brew_bin

  commands :brew => @brewbin
  commands :stat => '/usr/bin/stat'

  # git is used to read/write the tap's `homebrew.forceautoupdate` config. We
  # resolve it ourselves (rather than via `commands`) so a missing git never
  # makes the whole provider unsuitable -- it only disables force_auto_update.
  GIT_BIN = ['/usr/bin/git', '/opt/homebrew/bin/git', '/usr/local/bin/git'].find { |p| File.exist?(p) } || 'git'

  def run_brew(*args, **opts)
    self.class.run_brew(*args, **opts)
  end

  def run_owned(*cmd, **opts)
    self.class.run_owned(*cmd, **opts)
  end

  # Read every installed tap in a single call. `brew tap-info --installed --json`
  # returns an array of objects exposing the tap `name` (user/repo), its `path`
  # (the clone, used to read the git remote and the auto-update config) and a
  # boolean `trusted`. NOTE: the JSON `remote` field is nil on current Homebrew
  # (>= 4.3.0), so the URL is read from git, not from here.
  #
  # combine: false is required -- brew prints status chatter to stderr that
  # would otherwise corrupt JSON.parse.
  def self.installed_taps
    output = run_brew('tap-info', '--installed', '--json', combine: false)
    JSON.parse(output)
  rescue StandardError => e
    Puppet.debug("Could not read homebrew taps: #{e}")
    []
  end

  # Read a single-value git config key from the tap's clone. Returns nil when
  # the key is unset or the read fails. combine: false so a git warning on
  # stderr can't leak into the value.
  def self.git_config(path, key)
    return nil if path.nil? || path.to_s.empty?

    value = run_owned(GIT_BIN, '-C', path.to_s, 'config', '--get', key, combine: false).to_s.strip
    value.empty? ? nil : value
  rescue StandardError
    nil
  end

  # The tap's actual git remote. `brew tap-info --json` reports `remote` as nil
  # on current Homebrew, so read it from the clone's git config.
  def self.remote_url_for(path)
    git_config(path, 'remote.origin.url')
  end

  # Whether the tap is configured to auto-update on every `brew update`.
  def self.force_auto_update_for(path)
    git_config(path, 'homebrew.forceautoupdate') == 'true' ? :true : :false
  end

  # tap-info exposes a `trusted` boolean directly (true for official taps and
  # for taps recorded in trust.json), so no separate `brew trust` call is needed.
  def self.trust_state(tap)
    tap['trusted'] ? :true : :false
  end

  def self.instances
    tap_info = installed_taps.each_with_object({}) { |t, h| h[t['name'].to_s.downcase] = t }

    # `brew tap` enumerates tap directories on disk, including those with a
    # corrupted git repo that `brew tap-info --json` silently omits.
    all_names = begin
      run_brew('tap', combine: false).to_s.lines.map { |l| l.chomp.strip.downcase }.reject(&:empty?)
    rescue StandardError => e
      Puppet.debug("Could not enumerate taps via 'brew tap': #{e}")
      tap_info.keys
    end

    all_names.map do |name|
      if (tap = tap_info[name])
        new(
          :name              => name,
          :ensure            => :present,
          :path              => tap['path'],
          :url               => remote_url_for(tap['path']),
          :force_auto_update => force_auto_update_for(tap['path']),
          :trust             => trust_state(tap),
        )
      else
        Puppet.warning("homebrew_tap: '#{name}' is present on disk but missing from " \
                       "'brew tap-info --json' (possibly corrupted); only ensure is managed.")
        new(:name => name, :ensure => :present)
      end
    end
  end

  def self.prefetch(resources)
    instances.each do |provider|
      if (resource = resources[provider.name])
        resource.provider = provider
      end
    end
  end

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure] = :present
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def url
    @property_hash[:url]
  end

  def url=(value)
    @property_flush[:url] = value
  end

  def force_auto_update
    @property_hash[:force_auto_update]
  end

  def force_auto_update=(value)
    @property_flush[:force_auto_update] = value
  end

  def trust
    @property_hash[:trust]
  end

  def trust=(value)
    @property_flush[:trust] = value
  end

  def flush
    if @property_flush[:ensure] == :absent
      untap
      @property_hash = { :ensure => :absent }
    elsif @property_flush[:ensure] == :present
      tap
      # Resolve path from installed_taps once (avoids a separate tap_path call
      # per property), then apply any declared properties.
      fresh = self.class.installed_taps.find { |t| t['name'].to_s.downcase == resource[:name] }
      if fresh
        @property_hash = {
          :ensure            => :present,
          :path              => fresh['path'],
          :url               => self.class.remote_url_for(fresh['path']),
          :force_auto_update => self.class.force_auto_update_for(fresh['path']),
          :trust             => self.class.trust_state(fresh),
        }
      else
        @property_hash = { :ensure => :present }
      end
      wanted = { :force_auto_update => resource[:force_auto_update],
                 :trust             => resource[:trust] }.reject { |_, v| v.nil? }
      apply_properties(wanted)
      wanted.each { |k, v| @property_hash[k] = v }
    else
      # Existing tap: apply only drifted properties, update @property_hash in place.
      apply_properties(@property_flush)
      @property_flush.each { |k, v| @property_hash[k] = v }
    end
    @property_flush = {}
  end

  private

  def force?
    [true, :true].include?(resource[:force])
  end

  def tap
    args = ['tap']
    args << '--force' if force?
    args << resource[:name]
    args << resource[:url] if resource[:url]
    Puppet.debug("Tapping #{resource[:name]}")
    run_brew(*args)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not tap #{resource[:name]}: #{e}"
  end

  def untap
    args = ['untap']
    # brew refuses to untap while formulae/casks from the tap are installed
    # unless --force is given.
    args << '--force' if force?
    args << resource[:name]
    Puppet.debug("Untapping #{resource[:name]}")
    run_brew(*args)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not untap #{resource[:name]}: #{e}"
  end

  # Correct the git remote of an already-tapped repo in place, without a
  # destructive untap/re-tap.
  def set_remote(url)
    Puppet.debug("Setting custom remote for #{resource[:name]} to #{url}")
    run_brew('tap', '--custom-remote', resource[:name], url)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not set custom remote for #{resource[:name]}: #{e}"
  end

  def apply_properties(updates)
    set_remote(updates[:url]) if updates.key?(:url)
    apply_force_auto_update(updates[:force_auto_update]) if updates.key?(:force_auto_update)
    apply_trust(updates[:trust]) if updates.key?(:trust)
  end

  def apply_force_auto_update(value)
    dir = (@property_hash[:path] || tap_path).to_s
    return if dir.empty?

    if value == :true
      run_owned(GIT_BIN, '-C', dir, 'config', 'homebrew.forceautoupdate', 'true')
    elsif self.class.git_config(dir, 'homebrew.forceautoupdate')
      # Only unset when the key is actually present, so that any --unset failure
      # (permission, locked config) is a genuine error rather than git's exit-5
      # "nothing to unset" -- and it surfaces instead of being swallowed.
      run_owned(GIT_BIN, '-C', dir, 'config', '--unset', 'homebrew.forceautoupdate')
    end
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not set force_auto_update for #{resource[:name]}: #{e}"
  end

  def apply_trust(value)
    if value == :true
      Puppet.debug("Trusting #{resource[:name]}")
      run_brew('trust', '--tap', resource[:name])
    else
      Puppet.debug("Untrusting #{resource[:name]}")
      run_brew('untrust', '--tap', resource[:name])
    end
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not set trust for #{resource[:name]}: #{e}"
  end

  def tap_path
    run_brew('--repository', resource[:name], combine: false).to_s.strip
  end

  def query
    self.class.installed_taps.each do |tap|
      next unless tap['name'].to_s.downcase == resource[:name]

      return {
        :name              => resource[:name],
        :ensure            => :present,
        :url               => self.class.remote_url_for(tap['path']),
        :force_auto_update => self.class.force_auto_update_for(tap['path']),
        :trust             => self.class.trust_state(tap),
      }
    end
    nil
  end
end
