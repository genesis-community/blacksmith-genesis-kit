#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 et:
package Genesis::Hook::New::Blacksmith v4.0.0;

use strict;
use warnings;
use v5.20; # Genesis supports min perl v5.20.

BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook);

use Genesis qw/bail info run/;
use Genesis::UI qw(prompt_for prompt_for_boolean);

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->{features} = [];
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Get static IP
  my $ip;
  prompt_for('ip', 'line',
    'What static IP do you want to deploy this Blacksmith on?',
    '--validation ip', \$ip);

  # IaaS selection
  my $iaas;
  prompt_for('iaas', 'select',
    'What IaaS will this Blacksmith deploy services to?',
    '-o [vsphere]   VMWare vSphere',
    '-o [aws]       Amazon Web Services',
    '-o [azure]     Microsoft Azure',
    '-o [google]    Google Cloud Platform',
    '-o [openstack] OpenStack',
    '-o [external-bosh]  Deploy to an External Bosh Director',
    \$iaas);

  # Process IaaS-specific params
  $self->_process_iaas_params($iaas);

  # Broker TLS
  info("The Blacksmith broker can be configured to use TLS by default.");
  my $broker_tls;
  prompt_for_boolean(
    'Would you like to access the broker api and WebUI using https?',
    1, \$broker_tls);

  info(
    "\nBlacksmith Forges allow you to deploy different types of services, on-demand. This kit provides builtin support for the following:\n".
    "\tredis      - Redis Key-Value store (persistent or cache)\n".
    "\tpostgresql - PostgreSQL standalone and clustered databases\n".
    "\trabbitmq   - RabbitMQ message bus clusters\n".
    "\tmariadb    - MariaDB / MySQL standalone databases (EXPERIMENTAL)\n"
  );

  my @forges;
  my $do_redis;
  prompt_for_boolean(
    'Do you want to offer on-demand *Redis* services?',
    1, \$do_redis);
  push @forges, 'redis' if $do_redis;

  my $do_redis_tls;
  prompt_for_boolean(
    'Do you want to offer TLS for on-demand *Redis* services(Redis 6 only)?',
    1, \$do_redis_tls);

  my $do_postgresql;
  prompt_for_boolean(
    'Do you want to offer on-demand *PostgreSQL* services?',
    1, \$do_postgresql);
  push @forges, 'postgresql' if $do_postgresql;

  my $do_rabbitmq;
  prompt_for_boolean(
    'Do you want to offer on-demand *RabbitMQ* services?',
    1, \$do_rabbitmq);
  push @forges, 'rabbitmq' if $do_rabbitmq;

  my $do_rabbitmq_tls;
  prompt_for_boolean(
    'Do you want to offer TLS for on-demand *Rabbitmq* services?',
    1, \$do_rabbitmq_tls);

  my $do_mariadb;
  prompt_for_boolean(
    'Do you want to offer on-demand *MariaDB* / *MySQL* services?',
    1, \$do_mariadb);
  push @forges, 'mariadb' if $do_mariadb;

  my $do_shield_backups;
  prompt_for_boolean(
    'Do you want to enable automatic service backups via *S.H.I.E.L.D.*?',
    1, \$do_shield_backups);

  if ($do_shield_backups) {
    my $shield_store;
    prompt_for('shield_store', 'line',
      'What store (UUID or name) should S.H.I.E.L.D. use to store backups?',
      \$shield_store);

    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/shield", "store", "$shield_store");
  }

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

  return $self->done(1);
}

sub _process_iaas_params {
  my ($self, $iaas) = @_;

  if ($iaas eq 'aws') {
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
      'What security groups should the all deployed VMs be placed in?',
      \@aws_default_sgs);

    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/aws", "access_key", "$aws_access_key");

    info("\n\nBefore deploying, please be sure to import the keypair generated for you from ".
         "Vault into AWS console.\n\n".
         "First run the following command to get the public key:\n\n".
         "\tsafe get secret/$ENV{GENESIS_VAULT_PREFIX}/aws/ssh:public\n\n".
         "Then go to EC2 > Key Pairs > Import Key Pair and:\n\n".
         "\t1. Type 'vcap\@$ENV{GENESIS_ENVIRONMENT}' in the 'Key pair name' input box\n".
         "\t2. Paste the safe command output into the 'Public key contents' input box\n".
         "\t3. Click 'Import' button\n\n".
         "Now you can SSH into VMs deployed by this director using the generated key.\n");

    $self->{aws_region} = $aws_region;
    $self->{aws_default_sgs} = \@aws_default_sgs;
  }
  elsif ($iaas eq 'vsphere') {
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

    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/vsphere", "user", "$vsphere_user");
    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/vsphere", "address", "$vsphere_address");

    my $vsphere_dc;
    prompt_for('vsphere_dc', 'line',
      'What vCenter data center do you want to BOSH to deploy to?',
      \$vsphere_dc);

    my @vsphere_clusters;
    prompt_for('vsphere_clusters', 'multi-line', '-m 1',
      'What vCenter clusters do you want BOSH to deploy to?',
      \@vsphere_clusters);

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
    }
    else {
      @vsphere_persistents = @vsphere_ephemerals;
    }

    $self->{vsphere_dc} = $vsphere_dc;
    $self->{vsphere_clusters} = \@vsphere_clusters;
    $self->{vsphere_ephemerals} = \@vsphere_ephemerals;
    $self->{vsphere_persistents} = \@vsphere_persistents;
  }
  elsif ($iaas eq 'google') {
    my $google_project_id;
    prompt_for('google_project_id', 'line',
      'What is your GCP project ID?',
      \$google_project_id);

    my $google_json_key;
    prompt_for('google_json_key', 'block',
      'What are your GCP credentials (generally supplied as a JSON block)?',
      \$google_json_key);

    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/google", "json_key", "$google_json_key");

    $self->{google_project_id} = $google_project_id;
  }
  elsif ($iaas eq 'azure') {
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

    my $azure_resource_group;
    prompt_for('azure_resource_group', 'line',
      'What Azure Resource Group will BOSH be deploying VMs into?',
      \$azure_resource_group);

    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/azure", "client_id", "$azure_client_id");
    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/azure", "tenant_id", "$azure_tenant_id");
    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/azure", "subscription_id", "$azure_subscription_id");

    my $azure_default_sg;
    prompt_for('azure_default_sg', 'line',
      'What security group should be used as the BOSH default security group?',
      \$azure_default_sg);

    $self->{azure_resource_group} = $azure_resource_group;
    $self->{azure_default_sg} = $azure_default_sg;
  }
  elsif ($iaas eq 'openstack') {
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

    my $openstack_domain;
    prompt_for('openstack_domain', 'line',
      'What OpenStack Domain will BOSH be deployed in?',
      \$openstack_domain);

    my $openstack_project;
    prompt_for('openstack_project', 'line',
      'What OpenStack Project will BOSH be deployed in?',
      \$openstack_project);

    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds", "username", "$openstack_user");
    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds", "domain", "$openstack_domain");
    $self->vault->set("secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds", "project", "$openstack_project");

    my $openstack_region;
    prompt_for('openstack_region', 'line',
      'What OpenStack Region is BOSH being deployed to?',
      \$openstack_region);

    my $openstack_ssh_key;
    prompt_for('openstack_ssh_key', 'line',
      'What is the name of the OpenStack SSH key that should be used to enable SSH access to BOSH-deployed VMs?',
      \$openstack_ssh_key);

    my @openstack_default_sgs;
    prompt_for('openstack_default_sgs', 'multi-line',
      'What default security groups should be applied to VMs created by BOSH?',
      \@openstack_default_sgs);

    $self->{openstack_auth_url} = $openstack_auth_url;
    $self->{openstack_region} = $openstack_region;
    $self->{openstack_ssh_key} = $openstack_ssh_key;
    $self->{openstack_default_sgs} = \@openstack_default_sgs;
  }
}

sub _create_environment_file {
  my ($self, %opts) = @_;

  my $env_file = "$ENV{GENESIS_ROOT}/$ENV{GENESIS_ENVIRONMENT}.yml";
  open my $fh, ">", $env_file or bail("Cannot open $env_file for writing: $!");

  print $fh "---\n";
  print $fh "kit:\n";
  print $fh "  name:    $ENV{GENESIS_KIT_NAME}\n";
  print $fh "  version: $ENV{GENESIS_KIT_VERSION}\n";
  print $fh "  features:\n";
  print $fh "    - $opts{iaas}\n";

  for my $forge (@{$opts{forges}}) {
    print $fh "    - $forge\n";
  }

  if ($opts{broker_tls}) {
    print $fh "    - broker-tls\n";
  }

  if ($opts{do_redis_tls}) {
    print $fh "    - redis-tls\n";
  }

  if ($opts{do_rabbitmq_tls}) {
    print $fh "    - rabbitmq-tls\n";
  }

  if ($opts{do_shield_backups}) {
    print $fh "    - shield-backups\n";
  }

  print $fh "\n";
  print $fh "params:\n";
  print $fh "  env:   $ENV{GENESIS_ENVIRONMENT}\n";
  print $fh "\n";
  print $fh "  ip: $opts{ip}\n";

  # IaaS-specific parameters
  if ($opts{iaas} eq 'aws') {
    print $fh "\n";
    print $fh "  # AWS credentials are stored in the Vault at\n";
    print $fh "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/aws\n";
    print $fh "  #\n";
    print $fh "  aws_region: $self->{aws_region}\n";
    print $fh "  aws_default_sgs:\n";
    for my $sg (@{$self->{aws_default_sgs}}) {
      print $fh "    - $sg\n";
    }
  }
  elsif ($opts{iaas} eq 'vsphere') {
    print $fh "\n";
    print $fh "  # vCenter credentials are stored in the Vault at\n";
    print $fh "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/vsphere\n";
    print $fh "  #\n";
    print $fh "  vsphere_datacenter: $self->{vsphere_dc}\n";
    print $fh "  vsphere_clusters:\n";
    for my $c (@{$self->{vsphere_clusters}}) {
      print $fh "    - $c\n";
    }
    print $fh "\n";
    print $fh "  vsphere_ephemeral_datastores:\n";
    for my $ds (@{$self->{vsphere_ephemerals}}) {
      print $fh "    - $ds\n";
    }
    print $fh "  vsphere_persistent_datastores:\n";
    for my $ds (@{$self->{vsphere_persistents}}) {
      print $fh "    - $ds\n";
    }
  }
  elsif ($opts{iaas} eq 'google') {
    print $fh "\n";
    print $fh "  # GCP credentials are stored in the Vault at\n";
    print $fh "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/google\n";
    print $fh "  #\n";
    print $fh "  google_project: $self->{google_project_id}\n";
  }
  elsif ($opts{iaas} eq 'azure') {
    print $fh "\n";
    print $fh "  # Azure credentials are stored in the Vault at\n";
    print $fh "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/azure\n";
    print $fh "  #\n";
    print $fh "  azure_resource_group: $self->{azure_resource_group}\n";
    print $fh "  azure_default_sg:     $self->{azure_default_sg}\n";
  }
  elsif ($opts{iaas} eq 'openstack') {
    print $fh "\n";
    print $fh "  # Openstack credentials are stored in the Vault at\n";
    print $fh "  #   secret/$ENV{GENESIS_VAULT_PREFIX}/openstack/creds\n";
    print $fh "  #\n";
    print $fh "  openstack_auth_url: $self->{openstack_auth_url}\n";
    print $fh "  openstack_region:   $self->{openstack_region}\n";
    print $fh "  openstack_ssh_key:  $self->{openstack_ssh_key}\n";
    print $fh "  openstack_default_security_groups:\n";
    for my $sg (@{$self->{openstack_default_sgs}}) {
      print $fh "    - $sg\n";
    }
  }

  close $fh;

  return 1;
}

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

1;

