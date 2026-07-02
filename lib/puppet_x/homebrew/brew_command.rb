require 'etc'

module PuppetX
  module Homebrew
    # Shared brew-invocation logic for the custom Homebrew providers
    # (homebrew_tap, homebrew_pin, homebrew_service, homebrew_bundle).
    #
    # `extend` this module into a provider class that has already declared
    # `commands :brew => ...` and `commands :stat => '/usr/bin/stat'`. It then
    # exposes `detect_brew_bin` (to pick the brew path at class-load time) and
    # `run_brew` (which drops privileges to the brew owner, since Homebrew
    # refuses to run as root while Puppet usually does).
    module BrewCommand
      INTEL_BREW         = '/usr/local/bin/brew'.freeze
      APPLE_SILICON_BREW = '/opt/homebrew/bin/brew'.freeze

      # Locate the brew binary. The default prefix is architecture-dependent
      # (/opt/homebrew on Apple Silicon, /usr/local on Intel), so we pick the
      # path from the CPU model fact rather than from whichever path happens to
      # exist first (both prefixes can coexist under Rosetta 2). We still fall
      # back to the other prefix to support non-default install locations.
      def detect_brew_bin
        models = begin
          Facter.value('processors.models')
        rescue StandardError
          nil
        end

        candidates = if Array(models).any? { |model| model.to_s =~ /\AApple/ }
                       [APPLE_SILICON_BREW, INTEL_BREW]
                     else
                       [INTEL_BREW, APPLE_SILICON_BREW]
                     end

        candidates.find { |path| File.exist?(path) } || candidates.first
      end

      # Run a brew command as the user who owns the brew binary. Homebrew
      # refuses to run as root, but Puppet usually runs as root, so we drop
      # privileges to the brew owner.
      #
      # Pass `combine: false` for commands whose stdout must be parsed (e.g.
      # `--json`): brew writes status chatter ("Fetching...", JSON-API refresh
      # notices, env hints) to stderr, and combining it into stdout corrupts
      # JSON.parse.
      def run_brew(*args, combine: true)
        run_owned(command(:brew), *args, combine: combine)
      end

      # Run an arbitrary command as the brew owner, using the same privilege
      # drop as run_brew. Useful for tap-adjacent commands that are not `brew`
      # itself (e.g. `git config` on a tap's clone, which is owned by the brew
      # user). The owner is derived from the brew binary's ownership.
      #
      # `combine` controls whether stderr is merged into the returned stdout
      # (default true, matching Puppet's usual behaviour); set false when the
      # caller parses stdout.
      def run_owned(*cmd, combine: true)
        brew_path = command(:brew)
        owner     = stat('-nf', '%Uu', brew_path).to_i
        group     = stat('-nf', '%Ug', brew_path).to_i
        home      = Etc.getpwuid(owner).dir

        if owner.zero?
          raise Puppet::ExecutionFailure,
                'Homebrew does not support installations owned by the "root" user. ' \
                'Please check the ownership of the brew binary.'
        end

        # uid/gid can only be set when the current process is root.
        if Process.uid.zero?
          uid = owner
          gid = group
        else
          uid = nil
          gid = nil
        end

        opts = {
          :uid                => uid,
          :gid                => gid,
          :combine            => combine,
          # Reads must not trigger a network `brew update` mid-run.
          :custom_environment => { 'HOME' => home, 'HOMEBREW_NO_AUTO_UPDATE' => '1' },
          :failonfail         => true,
        }

        if Puppet.features.bundled_environment?
          Bundler.with_clean_env do
            Puppet::Util::Execution.execute(cmd, opts)
          end
        else
          Puppet::Util::Execution.execute(cmd, opts)
        end
      end
    end
  end
end
