# Apply a Brewfile. The shorthand form uses the resource name as the path.
homebrew_bundle { '/Users/travis/Brewfile':
  ensure => present,
}

# Named form with an explicit path and cleanup of unlisted packages.
homebrew_bundle { 'company-baseline':
  ensure  => present,
  path    => '/etc/homebrew/Brewfile',
  cleanup => true,
}
