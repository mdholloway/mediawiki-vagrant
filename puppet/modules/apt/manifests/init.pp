# == Class: apt
#
# This Puppet class configures Advanced Packaging Tool (APT), Debian's
# package management toolset, to catalog and install packages from
# supplementary sources.
#
class apt {
    exec { 'apt-get update':
        refreshonly => true,
    }

    exec { 'add ubuntu git maintainers apt key':
        command => 'apt-key add /vagrant/puppet/modules/apt/files/ubuntu-git-maintainers.key',
        unless  => 'apt-key list | grep -q "Launchpad PPA for Ubuntu Git Maintainers"',
    }

    apt::ppa { 'git-core/ppa':
        require => Exec['add ubuntu git maintainers apt key'],
    }

    exec { 'add wikimedia apt key':
        command => 'apt-key add /vagrant/puppet/modules/apt/files/wikimedia.key',
        unless  => 'apt-key list | grep -q Wikimedia',
    }

    file { '/etc/apt/sources.list.d/wikimedia.list':
        content => template('apt/wikimedia.list.erb'),
        require => Exec['add wikimedia apt key'],
        notify  => Exec['apt-get update'],
    }

    Apt::Ppa <| |> ~> Exec['apt-get update'] -> Package <| |>
}
