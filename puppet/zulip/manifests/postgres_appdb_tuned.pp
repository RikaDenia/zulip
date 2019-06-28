# postgres_appdb_tuned extends postgres_appdb_base by automatically
# generating tuned database configuration.
class zulip::postgres_appdb_tuned {
  include zulip::postgres_appdb_base

$postgres_conf_dir = $::osfamily ? {
  'debian' => "/etc/postgresql/${zulip::base::postgres_version}/main",
  'redhat' => "/var/lib/pgsql/${zulip::base::postgres_version}/data",
}
$postgres_restart = $::osfamily ? {
  'debian' => "pg_ctlcluster ${zulip::base::postgres_version} main restart",
  'redhat' => "systemctl restart postgresql-${zulip::base::postgres_version}",
}
$postgres_locale = $::osfamily ? {
  'debian' => "C.UTF-8",
  'redhat' => "en_US.UTF-8",
}
$postgres_data_dir = $::osfamily ? {
  'debian' => "/var/lib/postgresql/${zulip::base::postgres_version}/main",
  'redhat' => "/var/lib/pgsql/${zulip::base::postgres_version}/data/",
}
$postgres_conf = "$postgres_conf_dir/postgresql.conf"
if $zulip::base::release_name == 'trusty' {
  # tools for database setup
  $postgres_appdb_tuned_packages = ['pgtune']
  package { $postgres_appdb_tuned_packages: ensure => 'installed' }

  file { "${postgres_conf}.template":
    ensure  => file,
    require => Package[$zulip::postgres_appdb_base::postgresql],
    owner   => 'postgres',
    group   => 'postgres',
    mode    => '0644',
    content => template("zulip/postgresql/${zulip::base::postgres_version}/postgresql.conf.template.erb"),
  }

  $half_memory = $zulip::base::total_memory / 2
  $half_memory_pages = $half_memory / 4096

  file {'/etc/sysctl.d/40-postgresql.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content =>
"kernel.shmall = ${half_memory_pages}
kernel.shmmax = ${half_memory}

# These are the defaults on newer kernels
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
"
    }

  exec { 'sysctl_p':
    command     => '/sbin/sysctl -p /etc/sysctl.d/40-postgresql.conf',
    subscribe   => File['/etc/sysctl.d/40-postgresql.conf'],
    refreshonly => true,
  }

  exec { 'pgtune':
    require     => Package['pgtune'],
    # Let Postgres use half the memory on the machine
    command     => "pgtune -T Web -M ${half_memory} -i ${postgres_conf}.template -o ${postgres_conf}",
    refreshonly => true,
    subscribe   => File["${postgres_conf}.template"]
  }

  exec { "pg_ctlcluster ${zulip::base::postgres_version} main restart":
    require     => Exec['sysctl_p'],
    refreshonly => true,
    subscribe   => [ Exec['pgtune'], File['/etc/sysctl.d/40-postgresql.conf'] ]
  }
} else {
  $half_memory = $zulip::base::total_memory / 2
  $half_memory_pages = $half_memory / 4096

  $work_mem = $zulip::base::total_memory_mb / 512
  $shared_buffers = $zulip::base::total_memory_mb / 8
  $effective_cache_size = $zulip::base::total_memory_mb * 10 / 32
  $maintenance_work_mem = $zulip::base::total_memory_mb / 32

  $random_page_cost = zulipconf('postgresql', 'random_page_cost', undef)
  $effective_io_concurrency = zulipconf('postgresql', 'effective_io_concurrency', undef)
  $replication = zulipconf('postgresql', 'replication', undef)
  $listen_addresses = zulipconf('postgresql', 'listen_addresses', undef)

  $ssl_cert_file = zulipconf('postgresql', 'ssl_cert_file', undef)
  $ssl_key_file = zulipconf('postgresql', 'ssl_key_file', undef)
  $ssl_ca_file = zulipconf('postgresql', 'ssl_ca_file', undef)

  file { $postgres_conf:
    ensure  => file,
    require => Package[$zulip::postgres_appdb_base::postgresql],
    owner   => 'postgres',
    group   => 'postgres',
    mode    => '0644',
    content => template("zulip/postgresql/${zulip::base::postgres_version}/postgresql.conf.template.erb"),
  }

  if $::osfamily == 'redhat' {
    # conf.d doesn't exist on redhat...
    file { "$postgres_conf_dir/conf.d":
      ensure => 'directory',
      owner  => 'postgres',
      group  => 'postgres',
      mode   => '0644',
    }
    # ...and has no snake oil cert...
    exec { 'make_dummy_cert':
      command =>
        'cd /etc/ssl/certs && ./make-dummy-cert ssl-cert-snakeoil.pem',
      unless  => 'test -f /etc/ssl/certs/ssl-cert-snakeoil.pem'
    }
    file { "/etc/ssl/private":
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
    exec { 'make_dummy_key':
      command =>
        'cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key',
      unless  => 'test -f /etc/ssl/private/ssl-cert-snakeoil.key',
    }
    file { "/etc/ssl/private/ssl-cert-snakeoil.key":
      ensure => 'file',
      owner  => 'root',
      group  => 'postgres',
      mode   => '0640',
    }
    # ...and no log directory
    file { "/var/log/postgresql/":
      ensure => 'directory',
      owner  => 'postgres',
      group  => 'postgres',
      mode   => '0644',
    }
  }

  exec { $postgres_restart:
    require     => Package[$zulip::postgres_appdb_base::postgresql],
    refreshonly => true,
    subscribe   => [ File[$postgres_conf] ]
  }
}

}
