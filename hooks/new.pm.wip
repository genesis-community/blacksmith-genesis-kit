package Genesis::Hook::New::Blacksmith v3.0.0;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::New);

use Genesis qw/bail info run/;
use Genesis::UI qw(prompt_for prompt_for_boolean);

# init - Initialize the hook {{{
sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->{features} = [];
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

# }}}

# perform - Main hook execution {{{
sub perform {
  my ($self) = @_;
  my $env = $self->env;

  info("#Bu{Blacksmith Service Broker - New Environment Setup}\n\n");

  # Get static IP
  my $ip = $self->_get_static_ip();

  # IaaS selection
  my $iaas = $self->_select_iaas();

  # Process IaaS-specific params
  $self->_process_iaas_params($iaas);

  # Broker TLS configuration
  my $broker_tls = $self->_configure_broker_tls();

  # Select service forges
  my @forges = ();
  my ($do_redis_tls, $do_rabbitmq_tls) = (0, 0);
  ($self->_select_forges(\@forges, \$do_redis_tls, \$do_rabbitmq_tls));

  # Shield backup configuration
  my $do_shield_backups = $self->_configure_shield_backups();

  # Validate feature combinations
  $self->_validate_features(
    iaas => $iaas,
    forges => \@forges,
    broker_tls => $broker_tls,
    do_redis_tls => $do_redis_tls,
    do_rabbitmq_tls => $do_rabbitmq_tls,
    do_shield_backups => $do_shield_backups
  );

  # Create environment file
  $self->_create_environment_file(
    ip => $ip,
    iaas => $iaas,
    forges => \@forges,
    broker_tls => $broker_tls,
    do_redis_tls => $do_redis_tls,
    do_rabbitmq_tls => $do_rabbitmq_tls,
    do_shield_backups => $do_shield_backups
  );

  # Offer environment editor
  $self->_offer_environment_editor();

  info("\n#G{Environment file created successfully!}\n");
  info("Next steps:\n");
  info("  1. Review and edit the environment file if needed\n");
  info("  2. Run '#C{genesis deploy $ENV{GENESIS_ENVIRONMENT}}' to deploy Blacksmith\n");

  return $self->done(1);
}

# }}}

# _process_iaas_params - Process IaaS-specific parameters {{{
sub _process_iaas_params {
  my ($self, $iaas) = @_;

  # Dispatch to specific IaaS handler
  my $method = "_process_${iaas}_params";
  $method =~ s/-/_/g; # Convert external-bosh to external_bosh
  
  if ($self->can($method)) {
    $self->$method();
  } else {
    # For external-bosh or unknown IaaS, no additional params needed
    info("\nUsing $iaas configuration - no additional IaaS parameters required.\n");
  }
  
  return 1;
}

# }}}

# _create_environment_file - Create the environment YAML file {{{
sub _create_environment_file {
  my ($self, %opts) = @_;

  my $env_file = "$ENV{GENESIS_ROOT}/$ENV{GENESIS_ENVIRONMENT}.yml";
  
  # Generate YAML content
  my $yaml_content = $self->_generate_yaml_content(%opts);
  
  # Write to file
  open my $fh, ">", $env_file or bail("Cannot open $env_file for writing: $!");
  print $fh $yaml_content;
  close $fh;

  info("\nEnvironment file created at: #C{$env_file}\n");
  
  return 1;
}

# }}}

# _offer_environment_editor - Offer to edit the environment file {{{
sub _offer_environment_editor {
  my ($self) = @_;
  my $edit;
  prompt_for_boolean(
    'Would you like to edit the environment file?',
    1, \$edit);

  if ($edit) {
    my ($out, $rc) = run({interactive => 1}, '${EDITOR:-vim} $1', "$ENV{GENESIS_ROOT}/$ENV{GENESIS_ENVIRONMENT}.yml");
    bail("Editor failed with exit code $rc") if $rc != 0;
  }

  return 1;
}

# }}}

# _get_static_ip - Prompt for Blacksmith static IP {{{
sub _get_static_ip {
  my ($self) = @_;
  
  my $ip;
  prompt_for('ip', 'line',
    'What static IP do you want to deploy this Blacksmith on?',
    '--validation ip', \$ip);
  
  return $ip;
}

# }}}

# _select_iaas - Prompt for IaaS selection {{{
sub _select_iaas {
  my ($self) = @_;
  
  info("\n#Bu{Infrastructure Selection}\n\n");
  
  my $iaas;
  prompt_for('iaas', 'select',
    'What IaaS will this Blacksmith deploy services to?',
    '-o [vsphere]        VMWare vSphere',
    '-o [aws]            Amazon Web Services',
    '-o [azure]          Microsoft Azure',
    '-o [google]         Google Cloud Platform',
    '-o [openstack]      OpenStack',
    '-o [external-bosh]  Deploy to an External Bosh Director',
    \$iaas);
  
  return $iaas;
}

# }}}

# _configure_broker_tls - Configure broker TLS settings {{{
sub _configure_broker_tls {
  my ($self) = @_;
  
  info("\n#Bu{Security Configuration}\n\n");
  info("The Blacksmith broker can be configured to use TLS for secure communications.\n");
  
  my $broker_tls;
  prompt_for_boolean(
    'Would you like to access the broker API and WebUI using HTTPS?',
    1, \$broker_tls);
  
  return $broker_tls;
}

# }}}

# _select_forges - Select service forges to enable {{{
sub _select_forges {
  my ($self, $forges_ref, $redis_tls_ref, $rabbitmq_tls_ref) = @_;
  
  info("\n#Bu{Service Forge Selection}\n\n");
  info("Blacksmith Forges allow you to deploy different types of services on-demand.\n");
  info("This kit provides built-in support for the following:\n\n");
  info("  #C{redis}      - Redis Key-Value store (persistent or cache)\n");
  info("  #C{postgresql} - PostgreSQL standalone and clustered databases\n");
  info("  #C{rabbitmq}   - RabbitMQ message bus clusters\n");
  info("  #C{mariadb}    - MariaDB / MySQL standalone databases #Y{(EXPERIMENTAL)}\n\n");

  # Redis
  my $do_redis;
  prompt_for_boolean(
    'Do you want to offer on-demand #M{Redis} services?',
    1, \$do_redis);
  if ($do_redis) {
    push @$forges_ref, 'redis';
    
    # Redis TLS
    prompt_for_boolean(
      'Do you want to offer TLS encryption for Redis services? #Y{(Redis 6+ only)}',
      1, $redis_tls_ref);
  }

  # PostgreSQL
  my $do_postgresql;
  prompt_for_boolean(
    'Do you want to offer on-demand #M{PostgreSQL} services?',
    1, \$do_postgresql);
  push @$forges_ref, 'postgresql' if $do_postgresql;

  # RabbitMQ
  my $do_rabbitmq;
  prompt_for_boolean(
    'Do you want to offer on-demand #M{RabbitMQ} services?',
    1, \$do_rabbitmq);
  if ($do_rabbitmq) {
    push @$forges_ref, 'rabbitmq';
    
    # RabbitMQ TLS
    prompt_for_boolean(
      'Do you want to offer TLS encryption for RabbitMQ services?',
      1, $rabbitmq_tls_ref);
  }

  # MariaDB
  my $do_mariadb;
  prompt_for_boolean(
    'Do you want to offer on-demand #M{MariaDB/MySQL} services? #Y{(EXPERIMENTAL)}',
    0, \$do_mariadb);
  push @$forges_ref, 'mariadb' if $do_mariadb;
  
  return 1;
}

# }}}

# _configure_shield_backups - Configure Shield backup integration {{{
sub _configure_shield_backups {
  my ($self) = @_;
  
  info("\n#Bu{Backup Configuration}\n\n");
  
  my $do_shield_backups;
  prompt_for_boolean(
    'Do you want to enable automatic service backups via #M{S.H.I.E.L.D.}?',
    1, \$do_shield_backups);

  if ($do_shield_backups) {
    my $shield_store;
    prompt_for('shield_store', 'line',
      'What S.H.I.E.L.D. store (UUID or name) should be used for backups?',
      \$shield_store);

    # Store Shield configuration in vault
    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/shield", "store", "$shield_store");
  }
  
  return $do_shield_backups;
}

# }}}

# _process_aws_params - Process AWS-specific parameters {{{
sub _process_aws_params {
  my ($self) = @_;
  
  my $aws_region;
  prompt_for('aws_region', 'line',
    'What AWS region would you like to deploy to?',
    \$aws_region);

  my $aws_access_key;
  prompt_for('aws_access_key', 'line',
    'What is your AWS Access Key?',
    \$aws_access_key);

  my $aws_secret_key;
  prompt_for("$ENV{GENESIS_VAULT_PREFIX}/aws:secret_key", 'secret-line',
    'What is your AWS Secret Key?',
    \$aws_secret_key);

  my @aws_default_sgs;
  prompt_for('aws_default_sgs', 'multi-line',
    'What security groups should all deployed VMs be placed in?',
    \@aws_default_sgs);

  # Store credentials in vault
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/aws", "access_key", "$aws_access_key");

  # Display SSH key import instructions
  $self->_display_aws_ssh_instructions();

  # Store parameters for environment file
  $self->{aws_region} = $aws_region;
  $self->{aws_default_sgs} = \@aws_default_sgs;
}

# }}}

# _process_vsphere_params - Process vSphere-specific parameters {{{
sub _process_vsphere_params {
  my ($self) = @_;
  
  # vCenter connection details
  my $vsphere_address;
  prompt_for('vsphere_address', 'line',
    'What is the IP address of your VMWare vCenter Server Appliance?',
    '--validation ip', \$vsphere_address);

  my $vsphere_user;
  prompt_for('vsphere_user', 'line',
    'What username should BOSH use to authenticate with vCenter?',
    \$vsphere_user);

  my $vsphere_password;
  prompt_for("$ENV{GENESIS_VAULT_PREFIX}/vsphere:password", 'secret-line',
    'What is the password for the vCenter user?',
    \$vsphere_password);

  # Store credentials
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/vsphere", "user", "$vsphere_user");
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/vsphere", "address", "$vsphere_address");

  # Infrastructure configuration
  my $vsphere_dc;
  prompt_for('vsphere_dc', 'line',
    'What vCenter data center do you want BOSH to deploy to?',
    \$vsphere_dc);

  my @vsphere_clusters;
  prompt_for('vsphere_clusters', 'multi-line', '-m 1',
    'What vCenter clusters do you want BOSH to deploy to?',
    \@vsphere_clusters);

  # Datastore configuration
  my @vsphere_ephemerals;
  prompt_for('vsphere_ephemerals', 'multi-line', '-m 1',
    'What data stores do you wish to use for ephemeral (OS) disks?',
    \@vsphere_ephemerals);

  my $same_datastores;
  prompt_for_boolean(
    'Do you wish to use these same data stores for persistent (data) disks?',
    1, \$same_datastores);

  my @vsphere_persistents;
  if (!$same_datastores) {
    prompt_for('vsphere_persistents', 'multi-line', '-m 1',
      'What data stores do you wish to use for persistent (data) disks?',
      \@vsphere_persistents);
  } else {
    @vsphere_persistents = @vsphere_ephemerals;
  }

  # Store parameters
  $self->{vsphere_dc} = $vsphere_dc;
  $self->{vsphere_clusters} = \@vsphere_clusters;
  $self->{vsphere_ephemerals} = \@vsphere_ephemerals;
  $self->{vsphere_persistents} = \@vsphere_persistents;
}

# }}}

# _process_google_params - Process Google Cloud Platform parameters {{{
sub _process_google_params {
  my ($self) = @_;
  
  my $google_project_id;
  prompt_for('google_project_id', 'line',
    'What is your GCP project ID?',
    \$google_project_id);

  my $google_json_key;
  prompt_for('google_json_key', 'block',
    'What are your GCP credentials (generally supplied as a JSON block)?',
    \$google_json_key);

  # Store credentials
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/google", "json_key", "$google_json_key");

  # Store parameters
  $self->{google_project_id} = $google_project_id;
}

# }}}

# _process_azure_params - Process Azure parameters {{{
sub _process_azure_params {
  my ($self) = @_;
  
  # Service principal credentials
  my $azure_client_id;
  prompt_for('azure_client_id', 'line',
    'What is your Azure Client ID?',
    \$azure_client_id);

  my $azure_client_secret;
  prompt_for("$ENV{GENESIS_VAULT_PREFIX}/azure:client_secret", 'secret-line',
    'What is your Azure Client Secret?',
    \$azure_client_secret);

  my $azure_tenant_id;
  prompt_for('azure_tenant_id', 'line',
    'What is your Azure Tenant ID?',
    \$azure_tenant_id);

  my $azure_subscription_id;
  prompt_for('azure_subscription_id', 'line',
    'What is your Azure Subscription ID?',
    \$azure_subscription_id);

  # Resource configuration
  my $azure_resource_group;
  prompt_for('azure_resource_group', 'line',
    'What Azure Resource Group will BOSH be deploying VMs into?',
    \$azure_resource_group);

  # Store credentials
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/azure", "client_id", "$azure_client_id");
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/azure", "tenant_id", "$azure_tenant_id");
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/azure", "subscription_id", "$azure_subscription_id");

  # Security group
  my $azure_default_sg;
  prompt_for('azure_default_sg', 'line',
    'What security group should be used as the BOSH default security group?',
    \$azure_default_sg);

  # Store parameters
  $self->{azure_resource_group} = $azure_resource_group;
  $self->{azure_default_sg} = $azure_default_sg;
}

# }}}

# _process_openstack_params - Process OpenStack parameters {{{
sub _process_openstack_params {
  my ($self) = @_;
  
  # Authentication details
  my $openstack_auth_url;
  prompt_for('openstack_auth_url', 'line',
    'What is the Auth URL of your OpenStack cluster?',
    \$openstack_auth_url);

  my $openstack_user;
  prompt_for('openstack_user', 'line',
    'What username will be used to authenticate with OpenStack?',
    \$openstack_user);

  my $openstack_password;
  prompt_for("$ENV{GENESIS_VAULT_PREFIX}/openstack/creds:password", 'secret-line',
    'What password will be used to authenticate with OpenStack?',
    \$openstack_password);

  # Domain and project
  my $openstack_domain;
  prompt_for('openstack_domain', 'line',
    'What OpenStack Domain will BOSH be deployed in?',
    \$openstack_domain);

  my $openstack_project;
  prompt_for('openstack_project', 'line',
    'What OpenStack Project will BOSH be deployed in?',
    \$openstack_project);

  # Store credentials
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds", "username", "$openstack_user");
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds", "domain", "$openstack_domain");
  $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds", "project", "$openstack_project");

  # Region and SSH configuration
  my $openstack_region;
  prompt_for('openstack_region', 'line',
    'What OpenStack Region is BOSH being deployed to?',
    \$openstack_region);

  my $openstack_ssh_key;
  prompt_for('openstack_ssh_key', 'line',
    'What is the name of the OpenStack SSH key that should be used to enable SSH access to BOSH-deployed VMs?',
    \$openstack_ssh_key);

  # Security groups
  my @openstack_default_sgs;
  prompt_for('openstack_default_sgs', 'multi-line',
    'What default security groups should be applied to VMs created by BOSH?',
    \@openstack_default_sgs);

  # Store parameters
  $self->{openstack_auth_url} = $openstack_auth_url;
  $self->{openstack_region} = $openstack_region;
  $self->{openstack_ssh_key} = $openstack_ssh_key;
  $self->{openstack_default_sgs} = \@openstack_default_sgs;
}

# }}}

# _display_aws_ssh_instructions - Display AWS SSH key import instructions {{{
sub _display_aws_ssh_instructions {
  my ($self) = @_;
  
  info("\n#Bu{AWS SSH Key Import Instructions}\n\n");
  info("Before deploying, please import the SSH keypair generated for you:\n\n");
  info("1. Get the public key from Vault:\n");
  info("   #G{safe get secret/$ENV{GENESIS_VAULT_PREFIX}/aws/ssh:public}\n\n");
  info("2. In AWS Console, go to EC2 > Key Pairs > Import Key Pair\n\n");
  info("3. Import the key:\n");
  info("   - Key pair name: #C{vcap\@$ENV{GENESIS_ENVIRONMENT}}\n");
  info("   - Paste the public key from step 1\n");
  info("   - Click 'Import'\n\n");
  info("This will allow you to SSH into VMs deployed by Blacksmith.\n");
}

# }}}

# _validate_features - Validate feature combinations {{{
sub _validate_features {
  my ($self, %opts) = @_;
  
  my @errors;
  
  # Check TLS features without base forges
  if ($opts{do_redis_tls} && !grep { $_ eq 'redis' } @{$opts{forges}}) {
    push @errors, "redis-tls requires the redis forge to be enabled";
  }
  
  if ($opts{do_rabbitmq_tls} && !grep { $_ eq 'rabbitmq' } @{$opts{forges}}) {
    push @errors, "rabbitmq-tls requires the rabbitmq forge to be enabled";
  }
  
  # Check for at least one forge
  if (!@{$opts{forges}} || @{$opts{forges}} == 0) {
    warning("\n#Y{Warning:} No service forges selected. Blacksmith will not be able to provision any services.\n");
    my $continue;
    prompt_for_boolean(
      'Are you sure you want to continue without any service forges?',
      0, \$continue);
    bail("Aborting environment creation.") unless $continue;
  }
  
  # Report errors
  if (@errors) {
    error("\n#R{Configuration errors detected:}\n");
    for my $err (@errors) {
      error("  - $err\n");
    }
    bail("Please fix the configuration errors and try again.");
  }
  
  return 1;
}

# }}}

# _generate_yaml_content - Generate properly formatted YAML content {{{
sub _generate_yaml_content {
  my ($self, %opts) = @_;
  
  my $yaml = "---\n";
  
  # Kit configuration
  $yaml .= "kit:\n";
  $yaml .= "  name:    $ENV{GENESIS_KIT_NAME}\n";
  $yaml .= "  version: $ENV{GENESIS_KIT_VERSION}\n";
  $yaml .= "  features:\n";
  
  # IaaS feature
  $yaml .= "    - $opts{iaas}\n";
  
  # Forge features
  for my $forge (@{$opts{forges}}) {
    $yaml .= "    - $forge\n";
  }
  
  # Optional features
  $yaml .= "    - broker-tls\n" if $opts{broker_tls};
  $yaml .= "    - redis-tls\n" if $opts{do_redis_tls};
  $yaml .= "    - rabbitmq-tls\n" if $opts{do_rabbitmq_tls};
  $yaml .= "    - shield-backups\n" if $opts{do_shield_backups};
  
  # Parameters section
  $yaml .= "\nparams:\n";
  $yaml .= "  env: $ENV{GENESIS_ENVIRONMENT}\n";
  $yaml .= "\n";
  $yaml .= "  # Blacksmith IP address\n";
  $yaml .= "  ip: $opts{ip}\n";
  
  # IaaS-specific parameters
  $yaml .= $self->_generate_iaas_params($opts{iaas});
  
  return $yaml;
}

# }}}

# _generate_iaas_params - Generate IaaS-specific YAML parameters {{{
sub _generate_iaas_params {
  my ($self, $iaas) = @_;
  
  my $yaml = "";
  
  if ($iaas eq 'aws') {
    $yaml .= "\n";
    $yaml .= "  # AWS credentials are stored in the Vault at:\n";
    $yaml .= "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/aws\n";
    $yaml .= "  aws_region: $self->{aws_region}\n";
    $yaml .= "  aws_default_sgs:\n";
    for my $sg (@{$self->{aws_default_sgs}}) {
      $yaml .= "    - $sg\n";
    }
  }
  elsif ($iaas eq 'vsphere') {
    $yaml .= "\n";
    $yaml .= "  # vSphere credentials are stored in the Vault at:\n";
    $yaml .= "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/vsphere\n";
    $yaml .= "  vsphere_datacenter: $self->{vsphere_dc}\n";
    $yaml .= "  vsphere_clusters:\n";
    for my $c (@{$self->{vsphere_clusters}}) {
      $yaml .= "    - $c\n";
    }
    $yaml .= "\n";
    $yaml .= "  vsphere_ephemeral_datastores:\n";
    for my $ds (@{$self->{vsphere_ephemerals}}) {
      $yaml .= "    - $ds\n";
    }
    $yaml .= "  vsphere_persistent_datastores:\n";
    for my $ds (@{$self->{vsphere_persistents}}) {
      $yaml .= "    - $ds\n";
    }
  }
  elsif ($iaas eq 'google') {
    $yaml .= "\n";
    $yaml .= "  # GCP credentials are stored in the Vault at:\n";
    $yaml .= "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/google\n";
    $yaml .= "  google_project: $self->{google_project_id}\n";
  }
  elsif ($iaas eq 'azure') {
    $yaml .= "\n";
    $yaml .= "  # Azure credentials are stored in the Vault at:\n";
    $yaml .= "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/azure\n";
    $yaml .= "  azure_resource_group: $self->{azure_resource_group}\n";
    $yaml .= "  azure_default_sg:     $self->{azure_default_sg}\n";
  }
  elsif ($iaas eq 'openstack') {
    $yaml .= "\n";
    $yaml .= "  # OpenStack credentials are stored in the Vault at:\n";
    $yaml .= "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds\n";
    $yaml .= "  openstack_auth_url: $self->{openstack_auth_url}\n";
    $yaml .= "  openstack_region:   $self->{openstack_region}\n";
    $yaml .= "  openstack_ssh_key:  $self->{openstack_ssh_key}\n";
    $yaml .= "  openstack_default_security_groups:\n";
    for my $sg (@{$self->{openstack_default_sgs}}) {
      $yaml .= "    - $sg\n";
    }
  }
  
  return $yaml;
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
