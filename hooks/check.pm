package Genesis::Hook::Check::Blacksmith;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

# Parent class inheritance
use parent qw(Genesis::Hook::Check);

# Import required functions
use Genesis qw/bail info warning error run in_array new_enough/;
use File::Basename qw/dirname/;

# Include common utilities
do dirname(__FILE__) . '/_util.pm';

##
## Blacksmith Check Hook
##
## This hook performs pre-flight checks to ensure the environment is properly
## configured before deployment. It validates:
## 1. Cloud configuration (unless using external BOSH)
## 2. Runtime configuration
## 3. Environment parameters based on IaaS
## 4. Certificate validity
## 5. Version compatibility for upgrades
##

# init - Initialize the hook and check minimum Genesis version {{{1
sub init {
	my ($class, %ops) = @_;
	my $obj = $class->SUPER::init(%ops);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

# }}}

# perform - Main hook execution {{{1
sub perform {
	my ($self) = @_;
	my $ok = 1;

	# Version compatibility checks
	$ok = 0 unless $self->check_version_compatibility();

	# Cloud Config checks
	$ok = 0 unless $self->check_cloud_config();

	# Runtime Config checks
	$ok = 0 unless $self->check_runtime_config();

	# Environment Parameter checks
	$ok = 0 unless $self->check_environment_parameters();

	# Feature compatibility checks
	$ok = 0 unless $self->check_feature_compatibility();

	# Certificate checks
	$ok = 0 unless $self->check_certificates();

	return $self->done($ok);
}

# }}}

# check_cloud_config - Validate cloud config requirements {{{1
sub check_cloud_config {
	my ($self) = @_;

	$self->start_check('cloud-config');

	# Skip cloud config check for external BOSH or OCFP
	return $self->check_result('cloud-config', 'skipped', "not applicable for external-bosh/OCFP environments") 
		if $self->want_feature('external-bosh') || $self->want_feature('ocfp');
	
	return $self->check_result('cloud-config', 'failed', "no cloud config found") 
		unless $self->env->has_config('cloud');

	# Validate required cloud config components for Blacksmith
	# These are the minimal requirements for deploying service instances
	
	# Check for required VM types
	my @required_vm_types = qw(default small);
	for my $vm_type (@required_vm_types) {
		$self->has_entry('cloud-config', 'vm_type', $vm_type,
			msg => "VM type '$vm_type' is recommended for service deployments"
		);
	}
	
	# Check for required disk types
	my @required_disk_types = qw(default);
	for my $disk_type (@required_disk_types) {
		$self->has_entry('cloud-config', 'disk_type', $disk_type,
			msg => "Disk type '$disk_type' is required for persistent storage"
		);
	}
	
	# Check for required networks
	$self->has_entry('cloud-config', 'network', 'default',
		msg => "Network 'default' is required for service deployments"
	);
	
	# Check for compilation configuration
	$self->has_entry('cloud-config', 'compilation',
		msg => "Compilation configuration is required"
	);

	return $self->check_result('cloud-config');
}

# }}}

# check_environment_parameters - Validate environment-specific parameters {{{1
sub check_environment_parameters {
	my ($self) = @_;

	$self->start_check('environment');
	
	# Common required parameters
	$self->has_entry('environment', 'params', 'ip',
		required => 1, 
		msg => "Static IP address for Blacksmith is required"
	);
	
	# IaaS-specific parameter validation
	my $iaas = $self->_determine_iaas();
	
	if ($iaas eq 'vsphere') {
		# vSphere requires datastore configuration
		for my $ds_type (qw(ephemeral persistent)) {
			my $param_name = "vsphere_${ds_type}_datastores";
			$self->has_entry('environment', 'params', $param_name, 
				type => 'array', 
				required => 1,
				msg => "$ds_type datastore list is required for vSphere"
			);
		}
		
		# Check for required vSphere parameters
		for my $param (qw(vsphere_datacenter vsphere_clusters)) {
			$self->has_entry('environment', 'params', $param,
				required => 1,
				msg => "$param is required for vSphere deployments"
			);
		}
	}
	elsif ($iaas eq 'aws') {
		# AWS requires region and security groups
		$self->has_entry('environment', 'params', 'aws_region',
			required => 1,
			msg => "AWS region is required"
		);
		
		$self->has_entry('environment', 'params', 'aws_default_sgs',
			type => 'array',
			required => 1,
			msg => "AWS security groups are required"
		);
	}
	elsif ($iaas eq 'azure') {
		# Azure requires resource group and security group
		$self->has_entry('environment', 'params', 'azure_resource_group',
			required => 1,
			msg => "Azure resource group is required"
		);
		
		$self->has_entry('environment', 'params', 'azure_default_sg',
			required => 1,
			msg => "Azure default security group is required"
		);
	}
	elsif ($iaas eq 'google') {
		# GCP requires project ID
		$self->has_entry('environment', 'params', 'google_project',
			required => 1,
			msg => "Google Cloud project ID is required"
		);
	}
	elsif ($iaas eq 'openstack') {
		# OpenStack requires several parameters
		for my $param (qw(openstack_auth_url openstack_region openstack_ssh_key)) {
			$self->has_entry('environment', 'params', $param,
				required => 1,
				msg => "$param is required for OpenStack deployments"
			);
		}
		
		$self->has_entry('environment', 'params', 'openstack_default_security_groups',
			type => 'array',
			required => 1,
			msg => "OpenStack security groups are required"
		);
	}
	
	# Check broker TLS parameters if feature is enabled
	if ($self->want_feature('broker-tls')) {
		if ($self->env->lookup('params.blacksmith_port', 3000) == 3000) {
			$self->has_entry('environment', 'params', 'blacksmith_tls_port',
				msg => "Consider setting blacksmith_tls_port (defaults to 443) when using broker-tls"
			);
		}
	}

	return $self->check_result('environment');
}

# }}}

# _determine_iaas - Helper to determine which IaaS is being used {{{1
sub _determine_iaas {
	my ($self) = @_;
	
	# Check features for IaaS
	for my $iaas (qw(aws azure google openstack vsphere stackit)) {
		return $iaas if $self->want_feature($iaas);
	}
	
	# If using external-bosh or ocfp, we might not have an IaaS feature
	return 'unknown' if $self->want_feature('external-bosh') || $self->want_feature('ocfp');
	
	return 'none';
}

# }}}

# check_certificates - Validate certificate requirements {{{1
sub check_certificates {
	my ($self) = @_;
	my $env = $self->env;
	my $ok = 1;

	my $ip = $self->_get_blacksmith_ip();
	return 1 unless $ip; # Skip cert check if no IP is set
	info("Checking if our certificates match the director static IP ($ip)...");

	my $vault = $env->secrets_base;
	for my $cert (qw(tls/director tls/nats/server)) {
		if (!$self->vault->exists("$vault/$cert")) {
			info("    - $vault/$cert [#Y{MISSING}]");
		} else {
			my ($out, $rc) = run({stderr => '/dev/null'}, 'safe --quiet x509 validate "$1" --for "$2"', "$vault/$cert", "$ip");
			if ($rc == 0) {
				info("    - $vault/$cert [#G{OK}]");
			} else {
				info("    - $vault/$cert [#R{INVALID}]");
				my ($validation_out, $valid_rc) = run('safe x509 validate "$1" --for "$2" 2>&1', "$vault/$cert", "$ip");
				info("      %s", $validation_out);
				$ok = 0;
			}
		}
	}

	return $ok;
}

# }}}

# check_version_compatibility - Validate kit version upgrade compatibility {{{1
sub check_version_compatibility {
	my ($self) = @_;
	
	$self->start_check('version compatibility');
	
	my $exodus_data = $self->exodus_data;
	my $last_version = $exodus_data->{kit_version};
	
	# If no previous deployment, skip version check
	return $self->check_result('version compatibility', 'skipped', 'no previous deployment found')
		unless $last_version;
	
	# Check if upgrade is supported
	if ($last_version && !new_enough($last_version, "2.0.0")) {
		return $self->check_result(
			'version compatibility',
			'failed',
			"cannot upgrade from v$last_version directly to v3.x. Please upgrade to at least v2.0.0 first"
		);
	}
	
	return $self->check_result('version compatibility');
}

# }}}

# check_runtime_config - Validate runtime configuration {{{1
sub check_runtime_config {
	my ($self) = @_;
	
	$self->start_check('runtime-config');
	
	# Skip for external BOSH or OCFP
	return $self->check_result('runtime-config', 'skipped', 'not applicable for external-bosh/OCFP environments')
		if $self->want_feature('external-bosh') || $self->want_feature('ocfp');
	
	return $self->check_result('runtime-config', 'failed', 'no runtime config found')
		unless $self->env->has_config('runtime');
	
	# Could add specific runtime config checks here if needed
	# For example, checking for required addons
	
	return $self->check_result('runtime-config');
}

# }}}

# check_feature_compatibility - Validate feature combinations {{{1
sub check_feature_compatibility {
	my ($self) = @_;
	
	$self->start_check('feature compatibility');
	
	my @errors;
	
	# Check for conflicting forge TLS features without base forge
	if ($self->want_feature('redis-tls') && !$self->want_feature('redis')) {
		push @errors, "redis-tls feature requires redis forge to be enabled";
	}
	
	if ($self->want_feature('rabbitmq-tls') && !$self->want_feature('rabbitmq')) {
		push @errors, "rabbitmq-tls feature requires rabbitmq forge to be enabled";
	}
	
	# Check for shield features consistency
	if ($self->want_feature('shield-backups') && !$self->env->lookup('params.shield_url', undef)) {
		push @errors, "shield-backups feature requires shield connection parameters";
	}
	
	# Check OCFP feature compatibility
	if ($self->want_feature('ocfp')) {
		# OCFP implies external BOSH
		if ($self->want_feature('external-bosh')) {
			push @errors, "ocfp feature already implies external-bosh, no need to specify both";
		}
		
		# Check for required OCFP parameters
		unless ($self->env->lookup('params.ocfp_env', undef)) {
			push @errors, "ocfp feature requires params.ocfp_env to be set";
		}
	}
	
	if (@errors) {
		return $self->check_result(
			'feature compatibility',
			'failed',
			join("
", @errors)
		);
	}
	
	return $self->check_result('feature compatibility');
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
