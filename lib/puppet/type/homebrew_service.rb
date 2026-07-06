Puppet::Type.newtype(:homebrew_service) do
  @doc = <<-DOC
    Manages background services registered with `brew services` on macOS.

    Wraps `brew services start` / `brew services stop`. The formula providing
    the service must already be installed; manage the `package` resource first
    and let this service depend on it.

    @example Keep a service running
      homebrew_service { 'postgresql@14':
        ensure => running,
      }

    @example Stop a service
      homebrew_service { 'redis':
        ensure => stopped,
      }
  DOC

  ensurable do
    desc 'Whether the service should be `running` or `stopped`.'

    newvalue(:running) do
      provider.start
    end

    newvalue(:stopped) do
      provider.stop
    end

    defaultto :running

    def retrieve
      provider.status
    end
  end

  newparam(:name, :namevar => true) do
    desc 'The name of an installed formula that provides a brew service.'

    munge(&:downcase)
  end
end
