package Genesis::Hook::PreDeploy::Blacksmith v1.0.2;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/bail info warning error run new_enough/;
use JSON::PP;

# init - Initialize the hook {{{
sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

# }}}

# perform - Main hook execution {{{
sub perform {
  my ($self) = @_;
  my $env = $self->env;
  my $ok = 1;

  info("#Bu{Pre-deployment validation for Blacksmith}\n");

  # Version upgrade check
  $ok = 0 unless $self->check_version_upgrade();

  # Cloud config validation
  $ok = 0 unless $self->validate_cloud_config();

  # Shield integration setup
  if ($self->want_feature('shield-backups')) {
    $ok = 0 unless $self->setup_shield_integration();
  }

  # IaaS-specific validations
  $ok = 0 unless $self->validate_iaas_requirements();

  return $self->done($ok);
}

# }}}

# check_version_upgrade - Check for version compatibility and migrations {{{
sub check_version_upgrade {
  my ($self) = @_;
  my $env = $self->env;
  
  info("Checking version compatibility...\n");
  
  # Skip version check for OCFP
  if ($self->want_feature('ocfp')) {
    info("  Version check skipped for OCFP\n");
    return 1;
  }
  
  my $previous_version = $env->exodus_lookup('kit_version', undef);
  return 1 unless $previous_version; # No previous deployment
  
  # Check if upgrading from an older version that needs migration
  if (!new_enough($previous_version, "2.0.0")) {
    warning("  Upgrading from v$previous_version requires manual migration steps.\n");
    warning("  Please refer to the upgrade documentation before proceeding.\n");
    return 0;
  }
  
  info("  Version compatibility [#G{OK}]\n");
  return 1;
}

# }}}

# validate_cloud_config - Validate cloud config meets requirements {{{
sub validate_cloud_config {
  my ($self) = @_;
  my $env = $self->env;
  
  info("Validating cloud config requirements...\n");
  
  # Skip for external BOSH or OCFP
  if ($self->want_feature('external-bosh') || $self->want_feature('ocfp')) {
    info("  Cloud config validation skipped for external-bosh/OCFP\n");
    return 1;
  }
  
  # Get the manifest to check resource requirements
  my $manifest_json = $self->get_manifest_json();
  return 0 unless $manifest_json;
  
  my $manifest = eval { decode_json($manifest_json) };
  if ($@) {
    error("  Failed to parse manifest: $@\n");
    return 0;
  }
  
  # Extract and validate required resources
  my @errors;
  
  # Check instance groups have required fields
  for my $ig (@{$manifest->{instance_groups} || []}) {
    my $name = $ig->{name} || 'unknown';
    my @required = qw(azs instances jobs name networks stemcell vm_type);
    my @missing;
    
    for my $field (@required) {
      push @missing, $field unless exists $ig->{$field};
    }
    
    if (@missing) {
      push @errors, "Instance group '$name' missing: " . join(', ', @missing);
    }
  }
  
  if (@errors) {
    error("  Cloud config validation [#R{FAILED}]\n");
    for my $err (@errors) {
      error("    - $err\n");
    }
    return 0;
  }
  
  info("  Cloud config validation [#G{OK}]\n");
  return 1;
}

# }}}

# get_manifest_json - Get the deployment manifest as JSON {{{
sub get_manifest_json {
  my ($self) = @_;
  
  my $manifest_file = $ENV{GENESIS_MANIFEST_FILE};
  my $vars_file = $ENV{GENESIS_BOSHVARS_FILE};
  
  unless ($manifest_file && -f $manifest_file) {
    error("  Manifest file not found\n");
    return undef;
  }
  
  my ($output, $rc, $err) = run(
    {stderr => 0},
    'bosh int "$1" -l "$2" 2>/dev/null | spruce json',
    $manifest_file,
    $vars_file || '/dev/null'
  );
  
  if ($rc) {
    error("  Failed to process manifest: %s\n", $err || 'Unknown error');
    return undef;
  }
  
  return $output;
}

# }}}

# setup_shield_integration - Configure Shield backup integration {{{
sub setup_shield_integration {
  my ($self) = @_;
  my $env = $self->env;
  
  info("Setting up Shield integration...\n");
  
  # Check Shield CLI availability
  my ($shield_check, $shield_rc) = run({stderr => 0}, 'command -v shield >/dev/null 2>&1');
  if ($shield_rc != 0) {
    error("  Shield CLI is not installed.\n");
    error("  Please install Shield CLI from: https://github.com/shieldproject/shield\n");
    return 0;
  }
  
  # Validate Shield configuration parameters
  my @required_params = qw(
    meta.shield.admin_username
    meta.shield.admin_password
    meta.shield.address
    params.shield_username
    params.shield_password
    params.shield_tenant
  );
  
  my @missing;
  for my $param (@required_params) {
    my $value = $env->partial_manifest_lookup($param, undef);
    push @missing, $param unless $value;
  }
  
  if (@missing) {
    error("  Missing Shield configuration parameters:\n");
    for my $param (@missing) {
      error("    - $param\n");
    }
    return 0;
  }
  
  # Get Shield configuration
  my $shield_admin_username = $env->partial_manifest_lookup('meta.shield.admin_username');
  my $shield_admin_password = $env->partial_manifest_lookup('meta.shield.admin_password');
  my $shield_address = $env->partial_manifest_lookup('meta.shield.address');

  my $blacksmith_shield_username = $env->partial_manifest_lookup('params.shield_username');
  my $blacksmith_shield_password = $env->partial_manifest_lookup('params.shield_password');
  my $blacksmith_shield_tenant = $env->partial_manifest_lookup('params.shield_tenant');
  
  # Set up Shield environment
  $ENV{BLACKSMITH_SHIELD_USERNAME} = $blacksmith_shield_username;
  $ENV{BLACKSMITH_SHIELD_PASSWORD} = $blacksmith_shield_password;
  $ENV{BLACKSMITH_SHIELD_TENANT} = $blacksmith_shield_tenant;
  
  # Connect to Shield
  info("  Connecting to Shield at $shield_address...\n");
  my ($api_out, $api_rc) = run({stderr => 0}, 'shield api $1 blacksmith-shield -k', $shield_address);
  if ($api_rc != 0) {
    error("  Failed to connect to Shield API: %s\n", $api_out || 'Connection failed');
    return 0;
  }
  
  # Login to Shield
  info("  Authenticating with Shield...\n");
  my ($login_out, $login_rc) = run(
    {stderr => 0},
    'shield login -c blacksmith-shield --username $1 --password $2',
    $shield_admin_username,
    $shield_admin_password
  );
  if ($login_rc != 0) {
    error("  Failed to authenticate with Shield: %s\n", $login_out || 'Authentication failed');
    return 0;
  }
  
  # Import Shield configuration
  info("  Importing Shield backup configuration...\n");
  my $shield_template = $self->kit->path('manifests/templates/shield-backups-import.yml');
  
  unless (-f $shield_template) {
    error("  Shield import template not found: $shield_template\n");
    return 0;
  }
  
  my ($import_out, $import_rc) = run(
    {stderr => 0},
    'shield import -c blacksmith-shield <(spruce merge "$1")',
    $shield_template
  );
  if ($import_rc != 0) {
    error("  Failed to import Shield configuration: %s\n", $import_out || 'Import failed');
    return 0;
  }
  
  info("  Shield integration [#G{OK}]\n");
  return 1;
}

# }}}

# validate_iaas_requirements - Validate IaaS-specific requirements {{{
sub validate_iaas_requirements {
  my ($self) = @_;
  my $env = $self->env;
  
  info("Validating IaaS-specific requirements...\n");
  
  # Determine which IaaS is in use
  my $iaas = $self->_determine_iaas();
  
  if ($iaas eq 'vsphere') {
    return $self->_validate_vsphere_requirements();
  } elsif ($iaas eq 'aws') {
    return $self->_validate_aws_requirements();
  } elsif ($iaas eq 'azure') {
    return $self->_validate_azure_requirements();
  } elsif ($iaas eq 'google') {
    return $self->_validate_gcp_requirements();
  } elsif ($iaas eq 'openstack') {
    return $self->_validate_openstack_requirements();
  }
  
  info("  IaaS validation skipped for: $iaas\n");
  return 1;
}

# }}}

# _determine_iaas - Helper to determine which IaaS is being used {{{
sub _determine_iaas {
  my ($self) = @_;
  
  for my $iaas (qw(aws azure google openstack vsphere)) {
    return $iaas if $self->want_feature($iaas);
  }
  
  return 'external-bosh' if $self->want_feature('external-bosh');
  return 'ocfp' if $self->want_feature('ocfp');
  return 'unknown';
}

# }}}

# _validate_vsphere_requirements - Validate vSphere-specific requirements {{{
sub _validate_vsphere_requirements {
  my ($self) = @_;
  my $env = $self->env;
  
  # Check for required vSphere credentials in vault
  my $vault_base = $env->secrets_base;
  my @required_secrets = (
    "${vault_base}vsphere:password",
    "${vault_base}vsphere:user",
    "${vault_base}vsphere:address"
  );
  
  my @missing;
  for my $secret (@required_secrets) {
    unless ($self->env->vault->has($secret)) {
      push @missing, $secret;
    }
  }
  
  if (@missing) {
    error("  Missing vSphere credentials in vault:\n");
    for my $secret (@missing) {
      error("    - $secret\n");
    }
    return 0;
  }
  
  info("  vSphere requirements [#G{OK}]\n");
  return 1;
}

# }}}

# _validate_aws_requirements - Validate AWS-specific requirements {{{
sub _validate_aws_requirements {
  my ($self) = @_;
  my $env = $self->env;
  
  # Skip AWS credential validation for external-bosh or ocfp
  # When using external-bosh, BOSH director handles the AWS credentials
  if ($self->want_feature('external-bosh') || $self->want_feature('ocfp')) {
    info("  AWS credential validation skipped for external-bosh/OCFP\n");
    info("  AWS requirements [#G{OK}] (handled by BOSH director)\n");
    return 1;
  }
  
  # Check for required AWS credentials
  my $vault_base = $env->secrets_base;
  my @required_secrets = (
    "${vault_base}aws:access_key",
    "${vault_base}aws:secret_key"
  );
  
  my @missing;
  for my $secret (@required_secrets) {
    unless ($self->env->vault->has($secret)) {
      push @missing, $secret;
    }
  }
  
  if (@missing) {
    error("  Missing AWS credentials in vault:\n");
    for my $secret (@missing) {
      error("    - $secret\n");
    }
    return 0;
  }
  
  # Check for SSH key
  unless ($self->env->vault->has("${vault_base}aws/ssh:public")) {
    warning("  AWS SSH key not found in vault\n");
    warning("  Run 'genesis add-secrets' to generate it\n");
  }
  
  info("  AWS requirements [#G{OK}]\n");
  return 1;
}

# }}}

# _validate_azure_requirements - Validate Azure-specific requirements {{{
sub _validate_azure_requirements {
  my ($self) = @_;
  my $env = $self->env;
  
  # Check for required Azure credentials
  my $vault_base = $env->secrets_base;
  my @required_secrets = (
    "${vault_base}azure:client_id",
    "${vault_base}azure:client_secret",
    "${vault_base}azure:tenant_id",
    "${vault_base}azure:subscription_id"
  );
  
  my @missing;
  for my $secret (@required_secrets) {
    unless ($self->env->vault->has($secret)) {
      push @missing, $secret;
    }
  }
  
  if (@missing) {
    error("  Missing Azure credentials in vault:\n");
    for my $secret (@missing) {
      error("    - $secret\n");
    }
    return 0;
  }
  
  info("  Azure requirements [#G{OK}]\n");
  return 1;
}

# }}}

# _validate_gcp_requirements - Validate GCP-specific requirements {{{
sub _validate_gcp_requirements {
  my ($self) = @_;
  my $env = $self->env;
  
  # Check for required GCP credentials
  my $vault_base = $env->secrets_base;
  unless ($self->env->vault->has("${vault_base}google:json_key")) {
    error("  Missing GCP service account key in vault\n");
    error("    - ${vault_base}google:json_key\n");
    return 0;
  }
  
  info("  GCP requirements [#G{OK}]\n");
  return 1;
}

# }}}

# _validate_openstack_requirements - Validate OpenStack-specific requirements {{{
sub _validate_openstack_requirements {
  my ($self) = @_;
  my $env = $self->env;
  
  # Check for required OpenStack credentials
  my $vault_base = $env->secrets_base;
  my @required_secrets = (
    "${vault_base}openstack/creds:username",
    "${vault_base}openstack/creds:password",
    "${vault_base}openstack/creds:domain",
    "${vault_base}openstack/creds:project"
  );
  
  my @missing;
  for my $secret (@required_secrets) {
    unless ($self->env->vault->has($secret)) {
      push @missing, $secret;
    }
  }
  
  if (@missing) {
    error("  Missing OpenStack credentials in vault:\n");
    for my $secret (@missing) {
      error("    - $secret\n");
    }
    return 0;
  }
  
  info("  OpenStack requirements [#G{OK}]\n");
  return 1;
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
