class { 'homebrew':
  user             => 'travis',
  group            => 'admin',
  manage_update    => true,
  update_frequency => 86400,
}
