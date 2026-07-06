Puppet::Type.newtype(:homebrew_bundle) do
  @doc = <<-DOC
    Applies a Homebrew `Brewfile` via `brew bundle`.

    Idempotence is delegated to `brew bundle check`: when the Brewfile's
    dependencies are already satisfied the resource is in sync, otherwise
    `brew bundle install` runs. Optionally, `cleanup` removes anything not
    listed in the Brewfile.

    @example Apply a Brewfile
      homebrew_bundle { '/Users/admin/Brewfile':
        ensure => present,
      }

    @example Apply and prune extras
      homebrew_bundle { 'company-baseline':
        ensure  => present,
        path    => '/etc/homebrew/Brewfile',
        cleanup => true,
      }
  DOC

  ensurable do
    desc 'Whether the Brewfile should be applied (`present`).'
    defaultto :present

    newvalue(:present) do
      provider.create
    end
  end

  newparam(:name, :namevar => true) do
    desc 'An arbitrary identifier, or the Brewfile path when `path` is unset.'
  end

  newparam(:path) do
    desc 'Path to the Brewfile. Defaults to the resource name.'
  end

  newparam(:cleanup, :boolean => true) do
    desc 'Whether to run `brew bundle cleanup --force` after install.'
    newvalues(:true, :false)
    defaultto :false
  end

  # Allow `homebrew_bundle { '/path/to/Brewfile': }` shorthand.
  def brewfile
    self[:path] || self[:name]
  end
end
