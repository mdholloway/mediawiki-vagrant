# == Class: Thumbor
#
# This Puppet class installs and configures a Thumbor instance
#
# Thumbor is installed as a Python package, and as part of that,
# pip compiles lxml.
#
# === Parameters
#
# [*cfg_dir*]
#   Thumbor configuration directory. The directory will be generated by Puppet.
#
# [*log_dir*]
#   Thumbor log directory. The directory will be generated by Puppet.
#
# [*tmp_dir*]
#   Thumbor tmp directory. The directory will be generated by Puppet.
#
# [*statsd_port*]
#   Port the statsd instance runs on.
#
class thumbor (
    $cfg_dir,
    $log_dir,
    $tmp_dir,
    $statsd_port,
) {
    require_package('python-logstash')

    package { 'raven':
        provider => 'pip',
    }

    package { 'python-thumbor-wikimedia':
        ensure => 'present',
        notify => Exec['stop-and-disable-default-thumbor-service'],
    }

    exec { 'stop-and-disable-default-thumbor-service':
        command => '/bin/systemctl stop thumbor'
    }

    $statsd_host = 'localhost'
    $statsd_prefix = 'Thumbor'

    file { '/etc/firejail/thumbor.profile':
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        source  => 'puppet:///modules/thumbor/thumbor.profile',
        require => Package['firejail'],
    }

    file { '/etc/tinyrgb.icc':
        ensure  => present,
        source  => 'puppet:///modules/thumbor/tinyrgb.icc',
        require => Package['python-thumbor-wikimedia'],
    }

    file { $cfg_dir:
        ensure => directory,
    }

    file { $log_dir:
        ensure  => directory,
        group   => 'thumbor',
        mode    => '0775',
        require => Package['python-thumbor-wikimedia'],
    }

    file { $tmp_dir:
        ensure => directory,
    }

    file { "${cfg_dir}/10-thumbor.conf":
        ensure  => present,
        group   => 'thumbor',
        content => template('thumbor/10-thumbor.conf.erb'),
        mode    => '0640',
        require => [
            File[$cfg_dir],
            Package['python-thumbor-wikimedia'],
        ],
    }

    file { "${cfg_dir}/20-thumbor-logging.conf":
        ensure  => present,
        group   => 'thumbor',
        content => template('thumbor/20-thumbor-logging.conf.erb'),
        mode    => '0640',
        require => [
            File[$cfg_dir, $log_dir],
            Package['python-thumbor-wikimedia'],
        ],
    }

    file { "${cfg_dir}/60-thumbor-wikimedia.conf":
        ensure  => present,
        group   => 'thumbor',
        content => template('thumbor/20-thumbor-wikimedia.conf.erb'),
        mode    => '0640',
        require => [
            File[$cfg_dir],
            Package['python-thumbor-wikimedia'],
        ],
    }

    # This will generate a list of ports starting at 8889, with
    # as many ports as there are CPUs on the machine.
    $ports = sequence_array(8889, $::processorcount).map |$p| { String($p) }

    thumbor::service { $ports:
        tmp_dir   => $tmp_dir,
        cfg_files => File[
            "${cfg_dir}/10-thumbor.conf",
            "${cfg_dir}/20-thumbor-logging.conf",
            "${cfg_dir}/60-thumbor-wikimedia.conf"
        ],
    }

    varnish::backend { 'swift':
        host   => '127.0.0.1',
        port   => $::swift::port,
        onlyif => 'req.url ~ "^/images/.*"',
    }

    varnish::config { 'thumbor':
        content => template('thumbor/varnish.vcl.erb'),
        order   => 49, # Needs to be before default for vcl_recv override
    }

    $port = $::swift::port
    $project = $::swift::project
    $user = $::swift::user
    $key = $::swift::key

    # Since thumbor doesn't have the ability to create swift containers, we have to
    # create the sharded thumbnail containers ahead of time.
    exec { 'create-swift-thumbnail-containers':
        command   => '/usr/local/bin/mwscript extensions/WikimediaMaintenance/filebackend/setZoneAccess.php --wiki wiki --backend swift-backend',
        unless    => "swift -A http://127.0.0.1:${port}/auth/v1.0 -U ${project}:${user} -K ${key} stat wiki-dev-local-thumb.ff | grep -q wiki-dev-local-thumb.ff",
        require   => [
            Service[
                'swift-account-server',
                'swift-account-auditor',
                'swift-account-reaper',
                'swift-account-replicator',
                'swift-container-server',
                'swift-container-updater',
                'swift-container-replicator',
                'swift-container-sync',
                'swift-container-auditor',
                'swift-object-server',
                'swift-object-auditor',
                'swift-object-replicator',
                'swift-object-updater',
                'swift-proxy-server'
            ],
            Mediawiki::Settings['swift'],
        ],
        subscribe => Mediawiki::Settings['swift'],
    }

    cron { 'systemd-thumbor-tmpfiles-clean':
        minute   => '*',
        hour     => '*',
        monthday => '*',
        month    => '*',
        weekday  => '*',
        command  => "/bin/systemd-tmpfiles --clean --prefix=${tmp_dir}",
    }
}
