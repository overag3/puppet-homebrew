class homebrew::update {
  # Reuse the architecture-dependent prefix computed by homebrew::install rather
  # than recomputing it (init.pp evaluates install before declaring this class).
  $brew_root = $homebrew::install::brew_root

  $brew   = "${brew_root}/bin/brew"
  $marker = "${brew_root}/var/homebrew/.puppet-last-brew-update"

  # $update_frequency is expressed in seconds; find -mmin works in minutes.
  $frequency_minutes = $homebrew::update_frequency / 60

  # Refresh every git tap (official + third-party) at most once per interval.
  # The marker is only touched on success (&&), so a transient failure leaves it
  # untouched and is retried on the next run; `|| true` swallows that failure so
  # a network blip is not reported as a failed Puppet resource. Between intervals
  # the `unless` guard skips the exec, so the resource stays unchanged (no churn).
  exec { 'homebrew-update':
    command   => "/usr/bin/su ${homebrew::user} -c '(${brew} update && /usr/bin/touch ${marker}) || true'",
    unless    => "/usr/bin/find ${marker} -mmin -${frequency_minutes} | /usr/bin/grep -q .",
    logoutput => on_failure,
    timeout   => 300,
  }
}
