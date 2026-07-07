class homebrew::update {
  # Homebrew prefix depends on architecture (same logic as homebrew::install).
  if $facts['is_arm64'] {
    $brew_root = '/opt/homebrew'
  } else {
    $brew_root = '/usr/local'
  }

  $brew   = "${brew_root}/bin/brew"
  $marker = "${brew_root}/var/homebrew/.puppet-last-brew-update"

  # $update_frequency is expressed in seconds; find -mmin works in minutes.
  $frequency_minutes = $homebrew::update_frequency / 60

  # Refresh every git tap (official + third-party) at most once per interval.
  # The marker is only touched on success (&&), so a transient failure does not
  # freeze the interval and is retried on the next run. Between intervals the
  # `unless` guard skips the exec, so the resource stays unchanged (no churn).
  exec { 'homebrew-update':
    command   => "/usr/bin/su ${homebrew::user} -c '${brew} update' && /usr/bin/touch ${marker}",
    unless    => "/usr/bin/find ${marker} -mmin -${frequency_minutes} | /usr/bin/grep -q .",
    logoutput => on_failure,
    timeout   => 0,
  }
}
