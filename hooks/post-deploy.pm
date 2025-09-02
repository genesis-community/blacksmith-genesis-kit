package Genesis::Hook::PostDeploy::Blacksmith v1.0.9;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::PostDeploy);

use Genesis qw/info warning error bail run/;
use File::Basename qw/dirname/;

# Include common utilities
do(dirname(__FILE__) . '/_util.pm');

# init - Initialize the hook and check minimum Genesis version {{{
sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

# }}}

# perform - Execute post-deployment tasks for Blacksmith environments {{{
sub perform {
  my ($self) = @_;
  my $env = $self->env;

  if ($self->deploy_successful) {
    info("\n#G{✓} #M{%s} Blacksmith Service Broker deployed successfully!\n", $env->name);

    # Provide helpful post-deployment information
    $self->display_deployment_summary();

    # Run post-deployment validations
#    $self->validate_deployment();

    # Display next steps
    $self->display_next_steps();
  } else {
    error("\n#R{Error} Blacksmith deployment failed.\n");
    error("\nPlease check the deployment logs for errors.\n");
    error("Common issues to check:\n");
    error("  - Cloud config requirements\n");
    error("  - Network connectivity\n");
    error("  - IaaS credentials\n");
    error("  - Resource availability\n");
  }

  return $self->done();
}

# }}}

# display_deployment_summary - Display deployment summary information {{{
sub display_deployment_summary {
  my ($self) = @_;
  my $env = $self->env;
  my $cmd_with_env = $env->get_call_path_with_env();

  info("\n#Bu{Deployment Summary}\n\n");

  # Basic deployment info
  info("Environment:  #C{%s}\n", $env->name);
  info("Kit:          #C{%s v%s}\n", $ENV{GENESIS_KIT_NAME}, $ENV{GENESIS_KIT_VERSION});

  # IaaS information
  my $iaas = $self->_determine_iaas();
  info("IaaS:         #C{%s}\n", $iaas);

  # Enabled forges
  my @forges;
  push @forges, 'Redis' if $self->want_feature('redis');
  push @forges, 'PostgreSQL' if $self->want_feature('postgresql');
  push @forges, 'RabbitMQ' if $self->want_feature('rabbitmq');
  push @forges, 'MariaDB' if $self->want_feature('mariadb');

  if (@forges) {
    info("\nEnabled Service Forges:\n");
    for my $forge (@forges) {
      info("   #M{%s}\n", $forge);
    }
  } else {
    warning("\n#Y{Warning:} No service forges are enabled.\n");
  }

  # Security features
  info("\nSecurity Features:\n");
  info("   Broker TLS:  %s\n",
    $self->want_feature('broker-tls') ? '#G{Enabled}' : '#Y{Disabled}');
  info("   Redis TLS:   %s\n",
    $self->want_feature('redis-tls') ? '#G{Enabled}' : '#Y{Disabled}')
    if $self->want_feature('redis');
  info("   RabbitMQ TLS: %s\n",
    $self->want_feature('rabbitmq-tls') ? '#G{Enabled}' : '#Y{Disabled}')
    if $self->want_feature('rabbitmq');

  # Backup configuration
  if ($self->want_feature('shield-backups')) {
    info("\nBackup Configuration:\n");
    info("   Shield Backups: #G{Enabled}\n");
  }
}

# }}}

# validate_deployment - Run post-deployment validations {{{
sub validate_deployment {
  my ($self) = @_;
  my $env = $self->env;

  info("\n#Bu{Post-deployment Validation}\n\n");

  # Check Blacksmith API connectivity
  my $ip = $self->_get_blacksmith_ip();
  my $port = $self->want_feature('broker-tls')
    ? $env->lookup('params.blacksmith_tls_port', 443)
    : $env->lookup('params.blacksmith_port', 3000);
  my $scheme = $self->want_feature('broker-tls') ? 'https' : 'http';
  my $url = "$scheme://$ip:$port";

  info("Checking Blacksmith API availability (%s/v2/catalog)...\n", $url);
  my ($curl_out, $curl_rc) = run(
    {stderr => 0},
    'curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$%s/v2/catalog"',
    $url
  );

  if ($curl_rc == 0 && $curl_out =~ /^[23]\d\d$/) {
    info("  ✓ API endpoint is responding (HTTP %s)\n", $curl_out);
  } else {
    warning("  ✗ API endpoint is not responding\n");
    warning("  The service may still be starting up.\n");
  }

  # Check internal BOSH director if applicable
  unless ($self->want_feature('external-bosh') || $self->want_feature('ocfp')) {
    info("\nChecking internal BOSH director...\n");
    my $bosh_ip = $env->exodus_lookup('bosh_address', undef);
    if ($bosh_ip) {
      info("  Internal BOSH director: #C{%s}\n", $bosh_ip);
    } else {
      warning("  Internal BOSH director information not found\n");
    }
  }
}

# }}}

# display_next_steps - Display helpful next steps {{{
sub display_next_steps {
  my ($self) = @_;
  my $env = $self->env;
  my $cmd_with_env = $env->get_call_path_with_env();

  info("\n#Bu{Next Steps}\n\n");

  info("1. View deployment details:\n");
  info("   #G{%s info}\n\n", $cmd_with_env);

  info("2. Access the Blacksmith Web UI:\n");
  info("   #G{%s do visit}\n\n", $cmd_with_env);

  info("3. Register with Cloud Foundry (if applicable):\n");
  info("   #G{%s do register <cf-deployment>}\n\n", $cmd_with_env);

  info("4. Access the internal BOSH director:\n");
  info("   #G{%s do bosh}\n\n", $cmd_with_env);

  info("5. View the service catalog:\n");
  info("   #G{%s do boss catalog}\n\n", $cmd_with_env);

  if ($self->want_feature('shield-backups')) {
    info("6. Configure Shield backup schedules:\n");
    info("   Access Shield UI and configure backup policies\n\n");
  }

  info("For troubleshooting service provisioning issues:\n");
  info("  - Check BOSH tasks: #G{%s do bosh tasks}\n", $cmd_with_env);
  info("  - View BOSH VMs: #G{%s do bosh vms}\n", $cmd_with_env);
  info("  - Check logs: #G{%s do boss logs}\n\n", $cmd_with_env);
}

# }}}

# _determine_iaas - Helper to determine which IaaS is being used {{{
sub _determine_iaas {
  my ($self) = @_;

  for my $iaas (qw(aws azure google openstack vsphere)) {
    return uc($iaas) if $self->want_feature($iaas);
  }

  return 'External BOSH' if $self->want_feature('external-bosh');
  return 'OCFP' if $self->want_feature('ocfp');
  return 'Unknown';
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
