package Genesis::Hook::Blueprint::Blacksmith v1.0.3;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/bail info warning error in_array/;

##
## Blacksmith Blueprint Hook
##
## This hook generates the deployment manifest for Blacksmith by:
## 1. Processing feature flags to determine which components to include
## 2. Validating feature combinations
## 3. Adding appropriate manifest files based on selected features
##
## Supported feature categories:
## - IaaS: aws, azure, google, openstack, vsphere, stackit
## - BOSH: external-bosh, ocfp (implies external-bosh)
## - Forges: rabbitmq, redis, postgresql, mariadb, kubernetes
## - Addons: broker-tls, shield-*, redis-*, rabbitmq-*, cf-route-registrar
##

# init - Initialize the hook {{{1
sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

# }}}

# perform - Main hook execution {{{1
sub perform {
	my ($self) = @_;

	# Add base files
	$self->add_files(qw(
		manifests/blacksmith/blacksmith.yml
		manifests/releases/blacksmith.yml
	));

	# Validate features using modern pattern
	$self->validate_blacksmith_features();

	# Store the IaaS type for later use
	$ENV{OCFP_IAAS} = $self->env->iaas;

	# Process validated features
	my ($iaas_count, $external_bosh_count, $forge_count) = $self->process_features();

	# Apply post-processing based on features
	$self->apply_post_processing($iaas_count, $external_bosh_count);

	# Validate final configuration
	$self->validate_configuration($iaas_count, $external_bosh_count, $forge_count);

	return $self->done();
}

# }}}

# validate_blacksmith_features - Validate features using modern Genesis pattern {{{1
sub validate_blacksmith_features {
	my ($self) = @_;

	# Build valid features list with IaaS-specific additions
	my @valid_features = qw(
		external-bosh
		ocfp
		aws
		azure
		google
		openstack
		vsphere
		stackit
		rabbitmq
		redis
		postgresql
		mariadb
		kubernetes
		broker-tls
		shield-backups
		shield-agent
		redis-tls
		redis-dual-mode
		rabbitmq-tls
		rabbitmq-dual-mode
		rabbitmq-dashboard-registration
		rabbitmq-autoscale
		cf-route-registrar
		cf-integration
	);

	# Pre-validation custom checks
	my (@warnings, @errors) = ();

	# Check for required parameters based on features
	# Skip param validations for ocfp as it provides these via its reference architecture
	if ($self->want_feature('cf-route-registrar') && !$self->want_feature('ocfp')) {
		push @errors, "Feature 'cf-route-registrar' requires params.cf_domain to be defined"
			unless $self->env->lookup('params.cf_domain');
	}

	# IaaS-specific parameter validation
	# Skip param validations for ocfp as it provides these via its reference architecture
	if ($self->want_feature('external-bosh') && !$self->want_feature('ocfp')) {
		my $bosh_env = $self->env->lookup('params.bosh_environment');
		push @errors, "Feature 'external-bosh' requires params.bosh_environment"
			unless $bosh_env;
	}

	# Perform validation with modern pattern
	$self->validate_features(
		valid_features              => \@valid_features,
		deprecated_features         => {
			# Legacy feature migrations
			'minimum-vms'          => 'small-footprint',
			'broker-tls-enabled'   => 'broker-tls',

			# Features now default behavior
			'basic-auth' => {
				msg => '- basic authentication is now enabled by default',
				replace => []
			},

			# Removed features
			'experimental-k8s' => {
				msg => 'Experimental Kubernetes support has been removed. Use the kubernetes forge feature instead.',
				# No replace = invalid feature
			}
		},
		mutually_exclusive_features => {
			'iaas'     => [qw/aws azure google openstack vsphere stackit/],
			# ocfp requires external-bosh, so they are not mutually exclusive
			'redis-tls' => [qw/redis-dual-mode/],
			'rabbitmq-tls' => [qw/rabbitmq-dual-mode/]
		},
		warnings                    => \@warnings,
		errors                      => \@errors
	);
}

# }}}

# process_features - Process all configured features {{{1
sub process_features {
	my ($self) = @_;

	my $iaas_count = 0;
	my $external_bosh_count = 0;
	my $forge_count = 0;

	for my $feature ($self->features) {
		# Process BOSH-related features
		if ($self->is_bosh_feature($feature)) {
			$external_bosh_count += $self->process_bosh_feature($feature);
		}
		# Process IaaS features
		elsif ($self->is_iaas_feature($feature)) {
			$iaas_count += $self->process_iaas_feature($feature);
		}
		# Process forge features
		elsif ($self->is_forge_feature($feature)) {
			$forge_count += $self->process_forge_feature($feature);
		}
		# Process addon features
		elsif ($self->is_addon_feature($feature)) {
			$self->process_addon_feature($feature);
		}
		# Process custom ops files
		elsif (-f $self->env->path("ops/$feature.yml")) {
			my $ops_file = $self->env->path("ops/$feature.yml");
			$self->add_files($ops_file);
		}
	}

	return ($iaas_count, $external_bosh_count, $forge_count);
}

# }}}

# Feature detection methods {{{1

# is_bosh_feature - Check if feature is BOSH-related {{{2
sub is_bosh_feature {
	my ($self, $feature) = @_;
	return $feature =~ /^(ocfp|external-bosh)$/;
}
# }}}

# is_iaas_feature - Check if feature is IaaS-related {{{2
sub is_iaas_feature {
	my ($self, $feature) = @_;
	return $feature =~ /^(aws|azure|google|openstack|vsphere|stackit)$/;
}
# }}}

# is_forge_feature - Check if feature is forge-related {{{2
sub is_forge_feature {
	my ($self, $feature) = @_;
	return $feature =~ /^(rabbitmq|redis|postgresql|mariadb|kubernetes)$/;
}
# }}}

# is_addon_feature - Check if feature is addon-related {{{2
sub is_addon_feature {
	my ($self, $feature) = @_;
	return $feature =~ /^(broker-tls|shield-backups|shield-agent|redis-tls|redis-dual-mode|rabbitmq-tls|rabbitmq-dual-mode|rabbitmq-dashboard-registration|rabbitmq-autoscale|cf-route-registrar|cf-integration)$/;
}
# }}}

# }}}

# Feature processing methods {{{1

# process_bosh_feature - Process BOSH-related features {{{2
sub process_bosh_feature {
	my ($self, $feature) = @_;

	if ($feature eq 'ocfp') {
		# OCFP Ref Arch requires external bosh
		$self->add_files("manifests/blacksmith/external-bosh.yml");
		return 1;
	}
	elsif ($feature eq 'external-bosh') {
		$self->add_files("manifests/blacksmith/external-bosh.yml");
		return 1;
	}

	return 0;
}
# }}}

# process_iaas_feature - Process IaaS features {{{2
sub process_iaas_feature {
	my ($self, $feature) = @_;
	return 1;
}
# }}}

# process_forge_feature - Process forge features {{{2
sub process_forge_feature {
	my ($self, $feature) = @_;

	$self->add_files("manifests/forges/$feature.yml");
	return 1;
}
# }}}

# process_addon_feature - Process addon features {{{2
sub process_addon_feature {
	my ($self, $feature) = @_;

	if ($feature eq 'broker-tls') {
		$self->add_files("manifests/blacksmith/broker-tls.yml");
	}
	elsif ($feature eq 'shield-backups') {
		$self->add_files("manifests/blacksmith/shield-backups.yml");
	}
	elsif ($feature eq 'shield-agent') {
		$self->add_files(
			"manifests/blacksmith/shield-agent.yml",
			"manifests/releases/shield-agent.yml"
		);
	}
	elsif ($feature eq 'redis-tls') {
		$self->add_files("manifests/forges/redis-tls.yml");
	}
	elsif ($feature eq 'redis-dual-mode') {
		$self->add_files("manifests/forges/redis-dual-mode.yml");
	}
	elsif ($feature eq 'rabbitmq-tls') {
		$self->add_files("manifests/forges/rabbitmq-tls.yml");
	}
	elsif ($feature eq 'rabbitmq-dual-mode') {
		$self->add_files("manifests/forges/rabbitmq-dual-mode.yml");
	}
	elsif ($feature eq 'rabbitmq-dashboard-registration') {
		$self->add_files("manifests/forges/rabbitmq-dashboard-registration.yml");
	}
	elsif ($feature eq 'rabbitmq-autoscale') {
		$self->add_files("manifests/forges/rabbitmq-autoscale.yml");
	}
	elsif ($feature eq 'cf-route-registrar') {
		$self->add_files("manifests/blacksmith/cf-route-registrar.yml");
	}
  elsif ($feature eq 'cf-integration') {
		$self->add_files("ocfp/cf-integration.yml");
	}
}

# }}}

# }}}

# apply_post_processing - Apply post-processing based on features {{{1
sub apply_post_processing {
	my ($self, $iaas_count, $external_bosh_count) = @_;

	# Add internal BOSH if no external BOSH specified
	if ($external_bosh_count == 0) {
		$self->add_files("manifests/blacksmith/bosh.yml");
	}

	# Add the IaaS manifest only if we are not using the OCFP feature.
	if (!$self->want_feature("ocfp") && $iaas_count != 0) {
		$self->add_files("manifests/iaas/$ENV{OCFP_IAAS}.yml");

		if (!$self->want_feature("vsphere")) {
			# vSphere doesn't need a registry, but everyone else does...
			$self->add_files("manifests/addons/registry.yml");
		}
	}

	# Handle OCFP-specific files
	if ($self->want_feature("ocfp")) {
		$self->add_files(
			"ocfp/meta.yml",
			"ocfp/ocfp.yml",
			"ocfp/$ENV{OCFP_IAAS}/ocf.yml"
		);

		if ($self->want_feature("shield-backups")) {
			$self->add_files("ocfp/shield-backups.yml");
		}

		if ($self->want_feature("shield-agent")) {
			$self->add_files("ocfp/shield-agent.yml");
		}

	}
}

# }}}

# validate_configuration - Validate the final configuration {{{1
sub validate_configuration {
	my ($self, $iaas_count, $external_bosh_count, $forge_count) = @_;

	my @errors;

	# Validate IaaS selection
	if ($iaas_count == 0 && $external_bosh_count == 0) {
		push @errors, "You have not enabled an IaaS feature flag. Please specify one of: aws, azure, google, openstack, vsphere, stackit, or use external-bosh/ocfp.";
	}

	if ($iaas_count > 1) {
		push @errors, "You have enabled more than one IaaS feature flag. Please specify only one.";
	}

	# Validate forge selection
	if ($forge_count == 0) {
		push @errors, "You have not activated any Blacksmith Forges. Please specify at least one of: rabbitmq, redis, postgresql, mariadb, kubernetes.";
	}

	# Bail if we have errors
	if (@errors) {
		error("Blueprint validation failed:");
		for my $err (@errors) {
			error("  - %s", $err);
		}
		bail("Cannot continue with invalid configuration.");
	}
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
