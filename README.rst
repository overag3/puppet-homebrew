puppet-homebrew
===============

A Puppet Module to install Homebrew and manage Homebrew packages on Mac OSX.
This module can install using either homebrew or brewcask, along with a
fallback mode which attempts both.

This module supports Puppet version 4 and greater running on Ruby version 1.8.3
and greater. Note that versions of Ruby from 2.0.x to 2.2.x may no longer be
supported by Homebrew. For Puppet 3 support, please pin to version 1.7.1.

puppet-homebrew is available on the `Puppet Forge`_.

Usage
-----

Installing Packages
~~~~~~~~~~~~~~~~~~~

Use the Homebrew package provider like this:

.. code-block:: puppet

    class hightower::packages {
      pkglist = ['postgresql', 'nginx', 'git', 'tmux']

      package { $pkglist:
        ensure   => present,
        provider => brew,
      }
    }

The providers works as follows:

* ``provider => brew``: install using ``brew install <module>``. Do not use
  brewcask.
* ``provider => brewcask``: install using ``brew cask install <module>``. Only use
  brewcask.
* ``provider => homebrew``: attempt to install using ``brew install <module>``. On
  failure, use ``brew cask install <module>``

Tapping Repositories
~~~~~~~~~~~~~~~~~~~~

The recommended way to manage taps is the dedicated ``homebrew_tap`` type:

.. code-block:: puppet

    homebrew_tap { 'neovim/neovim':
      ensure => present,
    }

You can untap a repository by setting ensure to ``absent``.

To tap a private or non-GitHub repository, provide a custom git URL. The URL is
drift-corrected: if the tap's actual git remote no longer matches the declared
value, the remote is rewritten *in place* with ``brew tap --custom-remote``
(no destructive untap/re-tap, so the local clone is preserved).

.. code-block:: puppet

    homebrew_tap { 'mycompany/internal':
      ensure => present,
      url    => 'https://git.example.com/mycompany/homebrew-internal.git',
    }

Additional options are available for third-party taps:

.. code-block:: puppet

    homebrew_tap { 'mycompany/tools':
      ensure            => present,
      force_auto_update => true,  # git-pull the tap on every `brew update`
      trust             => true,  # `brew trust --tap` (see below)
      force             => true,  # `brew tap --force` (force-clone via the API)
    }

* ``force_auto_update`` — when ``true``, sets the tap's
  ``homebrew.forceautoupdate`` git config so Homebrew refreshes it on every
  ``brew update``; when ``false`` the setting is removed. (Homebrew dropped the
  ``brew tap --force-auto-update`` flag in 4.2.13, so this is managed via git
  config directly.)
* ``trust`` — runs ``brew trust --tap`` / ``brew untrust --tap``. Trusting a
  non-official tap is required to load its formulae, casks and commands once
  ``HOMEBREW_REQUIRE_TAP_TRUST`` is set (the default from Homebrew 6.0.0).
  Official ``homebrew/*`` taps are always trusted.
* ``force`` — passes ``--force`` to ``brew tap`` (e.g. to force-clone
  ``homebrew/cask`` even though it is otherwise served from the JSON API) and to
  ``brew untap`` (to allow ``ensure => absent`` even while formulae or casks from
  the tap are still installed, which ``brew untap`` refuses by default).

If unspecified, ``force_auto_update`` and ``trust`` are left unmanaged.

Declaring an official tap that has since been merged or built into Homebrew
(e.g. ``homebrew/cask-fonts``, ``homebrew/cask-versions``, ``homebrew/bundle``,
``homebrew/services``) still works but emits a deprecation warning.

Because ``homebrew_tap`` is a native type, you can inspect the currently tapped
repositories with ``puppet resource homebrew_tap``, and enforce that *only* the
declared taps exist (untapping any others) with a resource purge:

.. code-block:: puppet

    resources { 'homebrew_tap': purge => true }

The legacy ``tap`` package provider is still supported for backwards
compatibility but is deprecated in favour of ``homebrew_tap``:

.. code-block:: puppet

    package { 'neovim/neovim':
      ensure   => present,
      provider => tap,
    }

You can untap a repository by setting ensure to ``absent``.

Ordering Taps
^^^^^^^^^^^^^

When both tapping a repo and installing a package from that repository, it is
important to make sure the former happens first. This can be accomplished in a
few different ways: either by doing so on a per-package basis:

.. code-block:: puppet

    homebrew_tap { 'neovim/neovim':
      ensure => present,
    } ->
    package { 'neovim':
      ensure   => present,
      provider => homebrew,
    }

or by setting all taps to occur before all other usages of this package with
`Resource Collectors`_:

.. code-block:: puppet

    # pick whichever provider(s) are relevant
    Homebrew_tap <| |> -> Package <| provider == homebrew |>
    Homebrew_tap <| |> -> Package <| provider == brew |>
    Homebrew_tap <| |> -> Package <| provider == brewcask |>


Extra Environment Variables
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Besides ``github_token`` (which sets ``HOMEBREW_GITHUB_API_TOKEN``), arbitrary
``HOMEBREW_*`` variables can be written to ``/etc/environment`` via the
``homebrew_environment`` hash:

.. code-block:: puppet

    class { 'homebrew':
      user                 => 'kevin',
      homebrew_environment => {
        'HOMEBREW_NO_AUTO_UPDATE' => '1',
        'HOMEBREW_NO_ANALYTICS'   => '1',
      },
    }

Installing Brew
~~~~~~~~~~~~~~~

To install homebrew on a node (with a compiler already present!):

.. code-block:: puppet

    class { 'homebrew':
      user      => 'hightower',
      group     => 'developers',  # defaults to 'admin'
      multiuser => false,         # set to true to enable multiuser support for homebrew
    }

Installing homebrew as the root user is no longer supported (as of late 2016).
Please ensure you install brew as a standard (non-root) user.

Note that some users have reported confusion between the *puppet* user and the
*homebrew* user -- it is perfectly fine to run puppet as root, in fact this is
encouraged, but the homebrew user must be non-root (generally, the system's main
user account).

If you run puppet as a non-root user and set the ``homebrew::user`` to a
*different* non-root user, you may run into issues; namely, since this module
requires the puppet user act as the homebrew user, you may get a password
prompt on each run. This can be fixed by allowing the puppet user passwordless
sudo privileges to the homebrew user.

If you are looking for a multi-user installation, please be sure to set the
multi-user flag, eg.:

.. code-block:: puppet

    class { 'homebrew':
      user      => 'kevin',
      group     => 'all-users',
      multiuser => true,
    }

To install homebrew and a compiler (on Lion or later), eg.:

.. code-block:: puppet

    class { 'homebrew':
      user                       => 'kevin',
      command_line_tools_package => 'command_line_tools_for_xcode_os_x_lion_april_2013.dmg',
      command_line_tools_source  => 'http://devimages.apple.com/downloads/xcode/command_line_tools_for_xcode_os_x_lion_april_2013.dmg',
    }

N.B. the author of this module does not maintain a mirror to command_line_tools.
You may need to search for a copy if you use this method. At the time of this
writing, downloading the command line tools sometimes requires an Apple ID.
Sorry, dude!

Adding a Github Token
~~~~~~~~~~~~~~~~~~~~~

Homebrew uses a Github token in your environment to make your experience better
by:

- Reducing the rate limit on ``brew search`` commands
- Letting you tap your private repositories
- Allowing you to upload Gists of brew installation errors

To enable this feature, you can include:

.. code-block:: puppet

    class { 'homebrew':
      user         => 'kevin',
      github_token => 'MyT0k3n!',
    }

Here's a link to `create a personal access token`_ for Github.

Original Author
---------------

Original credit for this module goes to `kelseyhightower`_. This module was
forked to provide brewcask integration.

Credit for logic involved in tapping repositories goes to `gildas`_.

.. _create a personal access token: https://github.com/settings/tokens/new?scopes=&description=Homebrew
.. _gildas: https://github.com/gildas/puppet-homebrew
.. _kelseyhightower: https://github.com/kelseyhightower
.. _Puppet Forge: https://forge.puppetlabs.com/thekevjames/homebrew
.. _Resource Collectors: https://docs.puppet.com/puppet/latest/reference/lang_collectors.html
