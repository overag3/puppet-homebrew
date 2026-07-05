Puppet::Type.newtype(:homebrew_pin) do
  @doc = <<-DOC
    Pins a Homebrew formula so that `brew upgrade` will not update it.

    Wraps `brew pin` / `brew unpin`. The formula must already be installed for
    Homebrew to pin it; manage the `package` resource first and let this pin
    depend on it.

    @example Pin an installed formula
      homebrew_pin { 'postgresql@14':
        ensure => present,
      }
  DOC

  ensurable do
    desc 'Whether the formula should be pinned (`present`) or unpinned (`absent`).'
    defaultto :present
  end

  newparam(:name, :namevar => true) do
    desc 'The name of an installed formula to pin (e.g. postgresql@14).'

    munge(&:downcase)
  end
end
