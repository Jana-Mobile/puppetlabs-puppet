# Class: puppet::master
#
# This class installs and configures a Puppet master
#
# Parameters:
#   [*modulepath*]            - The modulepath configuration value used in
#                               puppet.conf
#   [*confdir*]               - The confdir configuration value in puppet.conf
#   [*manifest*]              - The manifest configuration value in puppet.conf
#   [*storeconfigs*]          - Boolean determining whether storeconfigs is
#                               to be enabled.
#   [*storeconfigs_dbadapter*] - The database adapter to use with storeconfigs
#   [*storeconfigs_dbuser*]   - The database username used with storeconfigs
#   [*storeconfigs_dbpassword*] - The database password used with storeconfigs
#   [*storeconfigs_dbserver*]   - Fqdn of the storeconfigs database server
#   [*storeconfigs_dbsocket*]   - The path to the mysql socket file
#   [*install_mysql_pkgs*]      - Boolean determining whether mysql and related
#                                 devel packages should be installed.
#   [*certname*]              - The certname configuration value in puppet.conf
#   [*autosign*]              - The autosign configuration value in puppet.conf
#   [*reports*]               - [array] of reports to generate
#   [*reporturl*]             - The URL used by the http reports processor to send reports
#   [*puppet_passenger*]      - Boolean value to determine whether puppet is
#                               to be run with Passenger
#   [*puppet_site*]           - The VirtualHost value used in the apache vhost
#                               configuration file when Passenger is enabled
#   [*puppet_docroot*]        - The DocumentRoot value used in the apache vhost
#                               configuration file when Passenger is enabled
#   [*puppet_vardir*]         - The path to the puppet vardir
#   [*puppet_passenger_port*] - The port on which puppet is listening when
#                               Passenger is enabled
#   [*puppet_master_package*]   - The name of the puppet master package
#   [*package_provider*]        - The provider used for package installation
#   [*version*]               - The value of the ensure parameter for the
#                               puppet master and agent packages
#
# Actions:
#
# Requires:
#
#  Class['concat']
#  Class['stdlib']
#  Class['concat::setup']
#  Class['mysql'] (conditionally)
#
# Sample Usage:
#
#  $modulepath = [
#    "/etc/puppet/modules/site",
#    "/etc/puppet/modules/dist",
#  ]
#
#  class { "puppet::master":
#    modulepath => inline_template("<%= modulepath.join(':') %>"),
#    dbadapter  => "mysql",
#    dbuser     => "puppet",
#    dbpassword => "password"
#    dbsocket   => "/var/run/mysqld/mysqld.sock",
#  }
#
class puppet::master (
  $modulepath                 = $::puppet::params::modulepath,
  $confdir                    = $::puppet::params::confdir,
  $manifest                   = $::puppet::params::manifest,
  $storeconfigs               = false,
  $storeconfigs_dbadapter     = $::puppet::params::storeconfigs_dbadapter,
  $storeconfigs_dbuser        = $::puppet::params::storeconfigs_dbuser,
  $storeconfigs_dbpassword    = $::puppet::params::storeconfigs_dbpassword,
  $storeconfigs_dbserver      = $::puppet::params::storeconfigs_dbserver,
  $storeconfigs_dbport        = undef,
  $storeconfigs_dbsocket      = $::puppet::params::storeconfigs_dbsocket,
  $install_mysql_pkgs         = $::puppet::params::puppet_storeconfigs_packages,
  $certname                   = $::fqdn,
  $autosign                   = false,
  $reports                    = ['log'],
  $reporturl                  = undef,
  $puppet_passenger           = false,
  $puppet_site                = $::puppet::params::puppet_site,
  $puppet_docroot             = $::puppet::params::puppet_docroot,
  $puppet_vardir              = $::puppet::params::puppet_vardir,
  $manage_vardir              = true,
  $puppet_passenger_port      = false,
  $puppet_master_package      = $::puppet::params::puppet_master_package,
  $package_provider           = undef,
  $puppet_master_service      = $::puppet::params::puppet_master_service,
  $puppet_central_ca          = undef,
  $puppetdb_terminus_package  = $::puppet::params::puppetdb_terminus_package,
  $puppetdb_terminus_version  = $::puppet::params::puppetdb_terminus_version,
  $proxy_allow_from           = [],
  $puppet_extra_configs       = {},
  $version                    = 'present'

) inherits puppet::params {

  include concat::setup

  File {
    require => Package[$puppet_master_package],
    owner   => 'puppet',
    group   => 'puppet',
  }

  if $storeconfigs {

    if $storeconfigs_dbadapter == "puppetdb" {
      class { 'puppet::storeconfigs':
        dbadapter                 => 'puppetdb',
        dbserver                  => $storeconfigs_dbserver,
        dbport                    => $storeconfigs_dbport,
        package_provider          => $package_provider,
        puppetdb_terminus_package => $puppetdb_terminus_package,
        puppetdb_terminus_version => $puppetdb_terminus_version
      }
    } else {
      class { 'puppet::storeconfigs':
        dbadapter  => $storeconfigs_dbadapter,
        dbuser     => $storeconfigs_dbuser,
        dbpassword => $storeconfigs_dbpassword,
        dbserver   => $storeconfigs_dbserver,
        dbsocket   => $storeconfigs_dbsocket,
      }
    }
  }

  if ! defined(Package[$puppet_master_package]) {
    package { $puppet_master_package:
      ensure   => $version,
      provider => $package_provider,
    }
  }

  if $puppet_passenger {
    $service_notify  = Service['httpd']
    $service_require = [Package[$puppet_master_package], Class['passenger']]

    Concat::Fragment['puppet.conf-master'] -> Service['httpd']

    exec { "Certificate_Check":
      command   => "puppet cert --generate ${certname} --trace",
      unless    => "/bin/ls ${puppet_ssldir}/certs/${certname}.pem",
      path      => "/usr/bin:/usr/local/bin",
      before    => Class['::passenger'],
      require   => Package[$puppet_master_package],
      logoutput => on_failure,
    }

    if ! defined(Class['passenger']) {
      class { '::passenger': }
    }

    if $puppet_central_ca {
      class { '::apache::mod::proxy': }
      class { '::apache::mod::proxy_http': }
    }

    $request_headers = ['unset X-Forwarded-For',
                        'set X-SSL-Subject %{SSL_CLIENT_S_DN}e',
                        'set X-Client-DN %{SSL_CLIENT_S_DN}e',
                        'set X-Client-Verify %{SSL_CLIENT_VERIFY}e']

    apache::vhost { "puppet-$puppet_site":
      port            => $puppet_passenger_port,
      priority        => '40',
      servername      => $puppet_site,
      docroot         => $puppet_docroot,
      request_headers => ['', '', '', ''],
      ssl             => true,
      ssl_cert        => "${puppet::params::puppet_ssldir}/certs/${certname}.pem",
      ssl_certs_dir   => "${puppet::params::puppet_ssldir}/certs",
      ssl_key         => "${puppet::params::puppet_ssldir}/private_keys/${certname}.pem",
      ssl_chain       => "${puppet::params::puppet_ssldir}/ca/ca_crt.pem",
      ssl_ca          => "${puppet::params::puppet_ssldir}/ca/ca_crt.pem",
      ssl_crl         => "${puppet::params::puppet_ssldir}/ca/ca_crl.pem",
      sslproxyengine  => true,
    # template        => 'puppet/apache2.conf.erb',
      custom_fragment => template('puppet/apache2.conf.erb'),
      require         => [ File['/etc/puppet/rack/config.ru'], File['/etc/puppet/puppet.conf'] ],
    }

    file { ["/etc/puppet/rack", "/etc/puppet/rack/public"]:
      ensure => directory,
      mode   => '0755',
    }

    file { "/etc/puppet/rack/config.ru":
      ensure  => link,
      target  => '/usr/share/puppet/ext/rack/files/config.ru',
      mode    => '0644',
      require => [ Package[$puppet_master_package], File['/etc/puppet/rack'] ]
    }

    concat::fragment { 'puppet.conf-master':
      order   => '05',
      target  => "/etc/puppet/puppet.conf",
      content => template("puppet/puppet.conf-master.erb"),
    }
  } else {

    $service_require = Package[$puppet_master_package]
    $service_notify = Exec['puppet_master_start']

    Concat::Fragment['puppet.conf-master'] -> Exec['puppet_master_start']

    concat::fragment { 'puppet.conf-master':
      order   => '05',
      target  => "/etc/puppet/puppet.conf",
      content => template("puppet/puppet.conf-master.erb"),
    }

    exec { 'puppet_master_start':
      command   => '/usr/bin/nohup puppet master &',
      refresh   => '/usr/bin/pkill puppet && /usr/bin/nohup puppet master &',
      unless    => "/bin/ps -ef | grep -v grep | /bin/grep 'puppet master'",
      require   => File['/etc/puppet/puppet.conf'],
      subscribe => Package[$puppet_master_package],
    }
  }

  if ! defined(Concat[$puppet_conf]) {
    concat { $puppet_conf:
      mode    => '0644',
      require => $service_require,
      notify  => $service_notify,
    }
  } else {
    Concat<| title == $puppet_conf |> {
      require => $service_require,
      notify  +> $service_notify,
    }
  }

  if ! defined(Concat::Fragment['puppet.conf-common']) {
    concat::fragment { 'puppet.conf-common':
      order   => '00',
      target  => $puppet_conf,
      content => template("puppet/puppet.conf-common.erb"),
    }
  }

  if $manage_vardir {
    file { $puppet_vardir:
      ensure       => directory,
      recurse      => true,
      recurselimit => '1',
      notify       => $service_notify,
    }
  }

  if defined(File['/etc/puppet']) {
    File ['/etc/puppet'] {
      require +> Package[$puppet_master_package],
      notify  +> $service_notify
    }
  }

}

