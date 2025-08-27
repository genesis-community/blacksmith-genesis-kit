package Genesis::Hook::Check::Blacksmith v1.0.4;

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
do(dirname(__FILE__) . '/_util.pm');

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
		if $self->wants_feature('external-bosh') || $self->wants_feature('ocfp');

	return $self->check_result('cloud-config', 'failed', "no cloud config found")
		unless $self->env->has_config('cloud');

	# Validate required cloud config components for Blacksmith
	# These are the minimal requirements for deploying service instances

	# Check for required VM types
	my @required_vm_types = qw(default small);
	for my $vm_type (@required_vm_types) {
		$self->has_entry('cloud-config', 'vm_type', $vm_type);
	}

	# Check for required disk types
	my @required_disk_types = qw(default);
	for my $disk_type (@required_disk_types) {
		$self->has_entry('cloud-config', 'disk_type', $disk_type);
	}

	# Check for required networks
	$self->has_entry('cloud-config', 'network', 'default');

	# Check for compilation configuration
	$self->has_entry('cloud-config', 'compilation');

	return $self->check_result('cloud-config');
}

# }}}

# check_environment_parameters - Validate environment-specific parameters {{{1
sub check_environment_parameters {
	my ($self) = @_;

	$self->start_check('environment');

	unless($self->wants_feature('ocfp')) {
		# Common required parameters
		# Check for required IP parameter
		my $has_ip = defined($self->env->lookup('params.ip', undef));
		$self->has_entry('environment', 'params', 'ip') unless $has_ip;
		if (!$has_ip) {
			error("Static IP address for Blacksmith is required (params.ip)");
		}
	}

	# IaaS-specific parameter validation
	my $iaas = $self->_determine_iaas();

	if ($iaas eq 'vsphere') {
		# vSphere requires datastore configuration
		for my $ds_type (qw(ephemeral persistent)) {
			my $param_name = "vsphere_${ds_type}_datastores";
			my $ds_value = $self->env->lookup("params.$param_name", undef);
			if (!defined($ds_value) || ref($ds_value) ne 'ARRAY') {
				error("$ds_type datastore list is required for vSphere (params.$param_name)");
			}
		}

		# Check for required vSphere parameters
		for my $param (qw(vsphere_datacenter vsphere_clusters)) {
			if (!defined($self->env->lookup("params.$param", undef))) {
				error("$param is required for vSphere deployments (params.$param)");
			}
		}
	}
	elsif ($iaas eq 'aws') {
		# AWS requires region and security groups (unless using OCFP where they come from vault)
		unless ($self->wants_feature('ocfp')) {
			if (!defined($self->env->lookup('params.aws_region', undef))) {
				error("AWS region is required (params.aws_region)");
			}

			my $sgs = $self->env->lookup('params.aws_default_sgs', undef);
			if (!defined($sgs) || ref($sgs) ne 'ARRAY') {
				error("AWS security groups are required (params.aws_default_sgs)");
			}
		}
	}
	elsif ($iaas eq 'azure') {
		# Azure requires resource group and security group
		if (!defined($self->env->lookup('params.azure_resource_group', undef))) {
			error("Azure resource group is required (params.azure_resource_group)");
		}

		if (!defined($self->env->lookup('params.azure_default_sg', undef))) {
			error("Azure default security group is required (params.azure_default_sg)");
		}
	}
	elsif ($iaas eq 'google') {
		# GCP requires project ID
		if (!defined($self->env->lookup('params.google_project', undef))) {
			error("Google Cloud project ID is required (params.google_project)");
		}
	}
	elsif ($iaas eq 'openstack') {
		# OpenStack requires several parameters
		for my $param (qw(openstack_auth_url openstack_region openstack_ssh_key)) {
			if (!defined($self->env->lookup("params.$param", undef))) {
				error("$param is required for OpenStack deployments (params.$param)");
			}
		}

		my $sgs = $self->env->lookup('params.openstack_default_security_groups', undef);
		if (!defined($sgs) || ref($sgs) ne 'ARRAY') {
			error("OpenStack security groups are required (params.openstack_default_security_groups)");
		}
	}

	# Check broker TLS parameters if feature is enabled (unless using OCFP)
	if ($self->wants_feature('broker-tls') && !$self->wants_feature('ocfp')) {
		if ($self->env->lookup('params.blacksmith_port', 3000) == 3000) {
			my $has_tls_port = defined($self->env->lookup('params.blacksmith_tls_port', undef));
			if (!$has_tls_port) {
				warning("Consider setting blacksmith_tls_port (defaults to 443) when using broker-tls");
			}
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
		return $iaas if $self->wants_feature($iaas);
	}

	# If using external-bosh or ocfp, we might not have an IaaS feature
	return 'unknown' if $self->wants_feature('external-bosh') || $self->wants_feature('ocfp');

	return 'none';
}

# }}}

# check_certificates - Validate certificate requirements {{{1
sub check_certificates {
	my ($self) = @_;
	my $env = $self->env;
	my $ok = 1;
	my $subject = "";

	if ($self->wants_feature('ocfp')) {
		info("ocfp uses route registrar, no need to check certificate.");
		return 1;
	} else {
		$subject = $self->_get_blacksmith_ip();
	}
	return 1 unless $subject; # Skip cert check if no IP is set
	info("Checking if our certificates match the director subject: ($subject)...");

	my $vault = $env->secrets_base;
	for my $cert (qw(tls/director tls/nats/server)) {
		if (!$self->env->vault->has("$vault$cert")) {
			info("    - $vault$cert [#Y{MISSING}]");
		} else {
			my ($out, $rc) = run({stderr => '/dev/null'}, 'safe --quiet x509 validate "$1" --for "$2"', "$vault$cert", "$subject");
			if ($rc == 0) {
				info("    - $vault$cert [#G{OK}]");
			} else {
				info("    - $vault$cert [#R{INVALID}]");
				my ($validation_out, $valid_rc) = run('safe x509 validate "$1" --for "$2" 2>&1', "$vault$cert", "$subject");
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

	# Skip version compatibility check for OCFP
	return $self->check_result('version compatibility', 'skipped', 'not applicable for OCFP environments')
		if $self->wants_feature('ocfp');

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
		if $self->wants_feature('external-bosh') || $self->wants_feature('ocfp');

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
	if ($self->wants_feature('redis-tls') && !$self->wants_feature('redis')) {
		push @errors, "redis-tls feature requires redis forge to be enabled";
	}

	if ($self->wants_feature('rabbitmq-tls') && !$self->wants_feature('rabbitmq')) {
		push @errors, "rabbitmq-tls feature requires rabbitmq forge to be enabled";
	}

#	# Check for shield features consistency
#	if ($self->wants_feature('shield-backups') && !$self->env->lookup('params.shield_url', undef)) {
#		push @errors, "shield-backups feature requires shield connection parameters";
#	}

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
