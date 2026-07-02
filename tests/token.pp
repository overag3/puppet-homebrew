class { 'homebrew':
  user                 => 'travis',
  group                => 'admin',
  github_token         => 'test-token-not-valid',
  homebrew_environment => {
    'HOMEBREW_NO_AUTO_UPDATE' => '1',
    'HOMEBREW_NO_ANALYTICS'   => '1',
  },
}
