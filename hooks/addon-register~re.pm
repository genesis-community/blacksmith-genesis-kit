package Genesis::Hook::Addon::Blacksmith::Register v3.0.0;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info warning error run new_enough/;
use File::Temp qw/tempdir/;

# init - Initialize the addon {{{
sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

# }}}

# cmd_details - Return command details {{{
sub cmd_details {
  return
    "Registers this Blacksmith Broker with a Genesis-deployed Cloud Foundry.\n".
    "Synchronizes CA certificates and enables service access for all forges.\n".
    "\n".
    "Usage: register [cf-environment-name]\n".
    "  If no CF environment name is provided, attempts to use the current\n".
    "  environment name with '/cf' suffix.\n".
    "\n".
    "Example: genesis do blacksmith-dev -- register cf-dev";
}

# }}}

# ca_sync - Helper method to sync CA certificates {{{
sub ca_sync {
  my ($self, $cf_env_name) = @_;
  my $env = $self->env;

  info("\n#Bu{Certificate Synchronization}\n\n");
  
  # Check if we need to sync certificates
  unless ($self->_needs_ca_sync()) {
    info("  Certificate sync not required for this configuration.\n");
    return 1;
  }
  
  info("Syncing Blacksmith CA certificates...\n");
  
  # Sync Blacksmith services CA
  my $broker_ca_path = $env->secrets_mount . '/' . $env->vault_prefix . '/broker/ca';
  
  # Check if CA exists
  unless ($self->vault->exists($broker_ca_path)) {
    warning("  Blacksmith broker CA not found at: $broker_ca_path\n");
    warning("  Skipping CA synchronization.\n");
    return 1;
  }
  
  info("  Setting blacksmith_services_ca in Credhub...\n");
  my ($out, $rc, $err) = run(
    {stderr => 0},
    'genesis credhub $1 set -t certificate -n "/$1-bosh/$1-blacksmith/blacksmith_services_ca" '.
    '-c <(safe get "$2:certificate") -p <(safe get "$2:key")',
    $env->name, $broker_ca_path
  );
  
  if ($rc != 0) {
    error("  Failed to set CA certificate in Credhub: %s\n", $err || 'Unknown error');
    return 0;
  }
  info("  ✓ Blacksmith services CA synchronized\n");

  # Sync NATS client certificate if needed
  my $exodus_path = $env->secrets_mount . '/exodus/' . $cf_env_name . '/cf';
  my $cf_vault_path = $env->secrets_mount . '/' . $env->vault_prefix =~ s/blacksmith/cf/r;
  
  if ($self->vault->exists("$exodus_path:nats_client_cert")) {
    info("  Setting nats_client_cert in Credhub...\n");
    
    ($out, $rc, $err) = run(
      {stderr => 0},
      'genesis credhub $1 set -t certificate -n "/$1-bosh/$1-cf/nats_client_cert" '.
      '-c <(safe get "$2:nats_client_cert") -p <(safe get "$2:nats_client_key") '.
      '-r <(safe get "$3/nats_ca:certificate")',
      $env->name, $exodus_path, $cf_vault_path
    );
    
    if ($rc != 0) {
      warning("  Failed to set NATS client certificate: %s\n", $err || 'Unknown error');
      warning("  This may not be critical - continuing.\n");
    } else {
      info("  ✓ NATS client certificate synchronized\n");
    }
  }

  return 1;
}

# }}}

# perform - Execute the addon command {{{
sub perform {
  my ($self) = @_;
  my $env = $self->env;

  info("#Bu{Blacksmith Service Broker Registration}\n");

  # Validate prerequisites
  unless ($self->_validate_prerequisites()) {
    return $self->done(0);
  }

  # Get CF environment name
  my $cf_env = $self->_determine_cf_environment();
  unless ($cf_env) {
    return $self->done(0);
  }

  # Sync CA certificates
  unless ($self->ca_sync($cf_env)) {
    warning("\nCertificate sync failed, but continuing with registration...\n");
  }

  # Get connection details
  my $connection_info = $self->_get_connection_info();
  my $cf_info = $self->_get_cf_info($cf_env);
  
  unless ($cf_info) {
    return $self->done(0);
  }

  # Connect to Cloud Foundry
  unless ($self->_connect_to_cf($cf_info)) {
    return $self->done(0);
  }

  # Register or update the service broker
  my $broker_name = "$cf_env-blacksmith";
  unless ($self->_register_service_broker($broker_name, $connection_info)) {
    return $self->done(0);
  }

  # Enable service access
  unless ($self->_enable_service_access($connection_info)) {
    return $self->done(0);
  }

  # Display success message
  info("\n#G{✓} Blacksmith successfully registered with Cloud Foundry!\n\n");
  info("Service broker name: #M{%s}\n", $broker_name);
  info("Cloud Foundry API:   #C{%s}\n\n", $cf_info->{api});
  info("To view available services:\n");
  info("  #G{cf marketplace}\n\n");
  info("To create a service instance:\n");
  info("  #G{cf create-service <service> <plan> <instance-name>}\n");

  return $self->done();
}

# }}}

# _validate_prerequisites - Check required tools are available {{{
sub _validate_prerequisites {
  my ($self) = @_;
  
  # Check for CF CLI
  my ($cf_check, $cf_rc) = run({stderr => 0}, 'command -v cf >/dev/null 2>&1');
  if ($cf_rc != 0) {
    error("\n#R{Error:} The Cloud Foundry CLI is not installed.\n");
    error("\nPlease install the CF CLI from:\n");
    error("  #C{https://github.com/cloudfoundry/cli#downloads}\n\n");
    return 0;
  }
  
  # Check for jq
  my ($jq_check, $jq_rc) = run({stderr => 0}, 'command -v jq >/dev/null 2>&1');
  if ($jq_rc != 0) {
    error("\n#R{Error:} The 'jq' command is not installed.\n");
    error("\nPlease install jq:\n");
    error("  - macOS:  #G{brew install jq}\n");
    error("  - Ubuntu: #G{apt-get install jq}\n");
    error("  - CentOS: #G{yum install jq}\n\n");
    return 0;
  }
  
  return 1;
}

# }}}

# _determine_cf_environment - Determine the CF environment name {{{
sub _determine_cf_environment {
  my ($self) = @_;
  
  my $cf_env = $self->{args}[0];
  
  if (!$cf_env) {
    # Try to infer from current environment name
    my $current_env = $self->env->name;
    
    # Common patterns: blacksmith-dev -> cf-dev
    if ($current_env =~ /^blacksmith-(.+)$/) {
      $cf_env = "cf-$1";
      info("\nNo CF environment specified. Inferring: #C{%s}\n", $cf_env);
    } else {
      error("\n#R{Error:} No Cloud Foundry environment name provided.\n\n");
      info("Usage: #G{genesis do %s -- register <cf-environment>}\n\n", $current_env);
      info("Example: #G{genesis do %s -- register cf-dev}\n\n", $current_env);
      return undef;
    }
  }
  
  return $cf_env;
}

# }}}

# _needs_ca_sync - Check if CA sync is needed {{{
sub _needs_ca_sync {
  my ($self) = @_;
  
  # CA sync is needed for certain features or when using internal services
  return 1 if $self->want_feature('broker-tls');
  return 1 if $self->want_feature('rabbitmq-tls');
  return 1 if $self->want_feature('redis-tls');
  
  return 0;
}

# }}}

# _get_connection_info - Get Blacksmith connection information {{{
sub _get_connection_info {
  my ($self) = @_;
  my $env = $self->env;
  
  my $vault = $env->secrets_mount . '/' . $env->vault_prefix;
  my $ip = $env->lookup('params.ip');
  my $fqdn = $env->lookup('params.fqdn', '');
  my $host = $fqdn || $ip;

  my ($port, $scheme);
  if ($self->want_feature('broker-tls')) {
    $port = $env->lookup('params.blacksmith_tls_port', 443);
    $scheme = 'https';
  } else {
    $port = $env->lookup('params.blacksmith_port', 3000);
    $scheme = 'http';
  }

  my $blacksmith_username = 'blacksmith';
  
  # Get password from vault
  my $blacksmith_password;
  eval {
    $blacksmith_password = $self->vault->get("$vault/broker:password");
  };
  if ($@) {
    bail("Failed to retrieve Blacksmith password from vault: %s", $@);
  }
  
  return {
    url => "$scheme://$host:$port",
    username => $blacksmith_username,
    password => $blacksmith_password
  };
}

# }}}

# _get_cf_info - Get Cloud Foundry connection information {{{
sub _get_cf_info {
  my ($self, $cf_env) = @_;
  my $env = $self->env;
  
  info("\nRetrieving Cloud Foundry information for #C{%s}...\n", $cf_env);
  
  # Get CF version to determine API format
  my $cf_version = $env->exodus_lookup("kit_version", undef, "$cf_env/cf");
  
  my $cf_api;
  if ($cf_version && new_enough($cf_version, "2.0.0-rc1")) {
    my $api_domain = $env->exodus_lookup("api_domain", undef, "$cf_env/cf");
    unless ($api_domain) {
      error("  Failed to find API domain for CF environment: %s\n", $cf_env);
      error("  Make sure the CF deployment has completed successfully.\n");
      return undef;
    }
    $cf_api = "https://$api_domain";
  } else {
    $cf_api = $env->exodus_lookup("api_url", undef, "$cf_env/cf");
    unless ($cf_api) {
      error("  Failed to find API URL for CF environment: %s\n", $cf_env);
      error("  This may be an older CF deployment or the exodus data is missing.\n");
      return undef;
    }
  }
  
  my $cf_user = $env->exodus_lookup("admin_username", undef, "$cf_env/cf");
  my $cf_pass = $env->exodus_lookup("admin_password", undef, "$cf_env/cf");
  
  unless ($cf_user && $cf_pass) {
    error("  Failed to retrieve CF admin credentials from exodus.\n");
    error("  Make sure the CF deployment has completed successfully.\n");
    return undef;
  }
  
  info("  CF API: #C{%s}\n", $cf_api);
  info("  Admin user: #M{%s}\n", $cf_user);
  
  return {
    api => $cf_api,
    username => $cf_user,
    password => $cf_pass
  };
}

# }}}

# _connect_to_cf - Connect and authenticate to Cloud Foundry {{{
sub _connect_to_cf {
  my ($self, $cf_info) = @_;
  
  # Create temporary home directory for CF CLI
  my $tempdir = tempdir("blacksmith.regXXXXXXX", CLEANUP => 1);
  local $ENV{HOME} = $tempdir;
  
  info("\nConnecting to Cloud Foundry...\n");
  
  # Target CF API
  info("  Setting API endpoint...\n");
  my ($api_out, $api_rc, $api_err) = run(
    {stderr => 0},
    'cf api "$1" --skip-ssl-validation',
    $cf_info->{api}
  );
  
  if ($api_rc != 0) {
    error("  Failed to connect to CF API: %s\n", $api_err || $api_out || 'Unknown error');
    return 0;
  }
  
  # Authenticate
  info("  Authenticating as %s...\n", $cf_info->{username});
  my ($auth_out, $auth_rc, $auth_err) = run(
    {stderr => 0},
    'cf auth "$1" "$2"',
    $cf_info->{username},
    $cf_info->{password}
  );
  
  if ($auth_rc != 0) {
    error("  Failed to authenticate: %s\n", $auth_err || $auth_out || 'Invalid credentials');
    return 0;
  }
  
  info("  ✓ Connected to Cloud Foundry\n");
  return 1;
}

# }}}

# _register_service_broker - Register or update the service broker {{{
sub _register_service_broker {
  my ($self, $broker_name, $connection_info) = @_;
  
  info("\nRegistering service broker...\n");
  
  # Check if broker already exists
  info("  Checking for existing broker...\n");
  my ($exists_out, $exists_rc) = run(
    {stderr => 0},
    'cf curl /v2/service_brokers | jq --arg name "$1" -r \'.resources[].entity | select(.name==$name) | .name\'',
    $broker_name
  );
  
  if ($exists_out && $exists_out =~ /\S/) {
    # Update existing broker
    info("  Updating existing service broker #M{%s}...\n", $broker_name);
    my ($update_out, $update_rc, $update_err) = run(
      {stderr => 0},
      'cf update-service-broker "$1" "$2" "$3" "$4"',
      $broker_name,
      $connection_info->{username},
      $connection_info->{password},
      $connection_info->{url}
    );
    
    if ($update_rc != 0) {
      error("  Failed to update service broker: %s\n", $update_err || $update_out || 'Unknown error');
      return 0;
    }
  } else {
    # Create new broker
    info("  Creating service broker #M{%s}...\n", $broker_name);
    my ($create_out, $create_rc, $create_err) = run(
      {stderr => 0},
      'cf create-service-broker "$1" "$2" "$3" "$4"',
      $broker_name,
      $connection_info->{username},
      $connection_info->{password},
      $connection_info->{url}
    );
    
    if ($create_rc != 0) {
      error("  Failed to create service broker: %s\n", $create_err || $create_out || 'Unknown error');
      return 0;
    }
  }
  
  info("  ✓ Service broker registered\n");
  return 1;
}

# }}}

# _enable_service_access - Enable access to all services {{{
sub _enable_service_access {
  my ($self, $connection_info) = @_;
  
  info("\nEnabling service access...\n");
  
  # Get service catalog
  info("  Retrieving service catalog...\n");
  my ($services_out, $services_rc, $services_err) = run(
    {stderr => 0},
    'curl -Lsk -u "$1:$2" "$3/v2/catalog" -H Accept:application/json | jq -r \'.services[].name\'',
    $connection_info->{username},
    $connection_info->{password},
    $connection_info->{url}
  );
  
  if ($services_rc != 0 || !$services_out) {
    error("  Failed to retrieve service catalog: %s\n", $services_err || 'Empty catalog');
    return 0;
  }
  
  my @service_names = split(/\s+/, $services_out);
  my $enabled_count = 0;
  
  for my $service_name (@service_names) {
    next unless $service_name =~ /\S/;
    
    info("  Enabling access for #C{%s}...\n", $service_name);
    my ($enable_out, $enable_rc) = run(
      {stderr => 0},
      'cf enable-service-access "$1" 2>&1',
      $service_name
    );
    
    if ($enable_rc != 0) {
      warning("    Failed to enable access: %s\n", $enable_out || 'Unknown error');
    } else {
      $enabled_count++;
    }
  }
  
  if ($enabled_count == 0) {
    error("  No services were enabled successfully.\n");
    return 0;
  }
  
  info("  ✓ Enabled access for %d service(s)\n", $enabled_count);
  return 1;
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
