class homebrew (
  $user,
  $command_line_tools_package = undef,
  $command_line_tools_source  = undef,
  $github_token               = undef,
  $group                      = 'admin',
  $multiuser                  = false,
  Boolean $manage_update      = false,
  Integer $update_frequency   = 86400,
  Hash[String, String] $homebrew_environment = {},
) {
  if $facts['os']['name'] != 'Darwin' {
    fail('This Module works on Mac OSX only!')
  }

  if $homebrew::user == 'root' {
    fail('Homebrew does not support installation as the "root" user.')
  }

  class { 'homebrew::compiler': }
  -> class { 'homebrew::install': }

  contain 'homebrew::compiler'
  contain 'homebrew::install'

  if $manage_update {
    class { 'homebrew::update': }
    contain 'homebrew::update'
    Class['homebrew::install'] -> Class['homebrew::update']
  }

  # HOMEBREW_GITHUB_API_TOKEN keeps its dedicated parameter for backwards
  # compatibility; any additional HOMEBREW_* variable can be set through the
  # $homebrew_environment hash (e.g. { 'HOMEBREW_NO_AUTO_UPDATE' => '1' }).
  $_environment = $homebrew::github_token ? {
    undef   => $homebrew::homebrew_environment,
    default => $homebrew::homebrew_environment + { 'HOMEBREW_GITHUB_API_TOKEN' => $homebrew::github_token },
  }

  unless empty($_environment) {
    ensure_resource('file', '/etc/environment', { 'ensure' => 'file' })

    $_environment.each |$var, $value| {
      file_line { "homebrew-environment-${var}":
        path    => '/etc/environment',
        line    => "${var}=${value}",
        match   => "^${var}=",
        require => File['/etc/environment'],
      }
    }
  }
}
