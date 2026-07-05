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

To tap into new Github repositories, simply use the tap provider:

.. code-block:: puppet

    package { 'neovim/neovim':
      ensure   => present,
      provider => tap,
    }

Ordering Taps
^^^^^^^^^^^^^

When both tapping a repo and installing a package from that repository, it is
important to make sure the former happens first. This can be accomplished in a
few different ways: either by doing so on a per-package basis:

.. code-block:: puppet

    package { 'neovim/neovim':
      ensure   => present,
      provider => tap,
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

Pinning Formulae
~~~~~~~~~~~~~~~~~

Pin an installed formula so ``brew upgrade`` leaves it untouched, using the
native ``homebrew_pin`` type. The formula must already be installed:

.. code-block:: puppet

    package { 'postgresql@14':
      ensure   => present,
      provider => brew,
    }
    -> homebrew_pin { 'postgresql@14':
      ensure => present,
    }

Set ``ensure => absent`` to unpin.

Managing Services
~~~~~~~~~~~~~~~~~

Manage ``brew services`` background daemons with the native ``homebrew_service``
type:

.. code-block:: puppet

    homebrew_service { 'postgresql@14':
      ensure  => running,   # or 'stopped'
      require => Package['postgresql@14'],
    }

Applying a Brewfile
~~~~~~~~~~~~~~~~~~~

Apply a ``Brewfile`` declaratively with ``homebrew_bundle``. Idempotence is
delegated to ``brew bundle check``:

.. code-block:: puppet

    homebrew_bundle { '/Users/kevin/Brewfile':
      ensure => present,
    }

    # named form with an explicit path and pruning of unlisted packages
    homebrew_bundle { 'company-baseline':
      ensure  => present,
      path    => '/etc/homebrew/Brewfile',
      cleanup => true,
    }

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
