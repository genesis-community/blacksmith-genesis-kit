package Genesis::Hook::Blueprint::Blacksmith v1.3.0;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/bail info warning error in_array mkdir_or_fail mkfile_or_fail/;
use File::Basename qw/dirname/;

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
## - Addons: broker-tls, shield-*, redis-*, rabbitmq-*, cf-route-registrar,
##   cf-integration, cf-haproxy-ca
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
		valkey
		postgresql
		mariadb
		kubernetes
		broker-tls
		shield-backups
		shield-agent
		redis-tls
		redis-dual-mode
		valkey-tls
		valkey-dual-mode
		rabbitmq-tls
		rabbitmq-dual-mode
		rabbitmq-dashboard-registration
		rabbitmq-autoscale
		cf-route-registrar
		cf-integration
		cf-haproxy-ca
	);

	# Pre-validation custom checks
	my (@warnings, @errors) = ();

	# Check for required parameters based on features
	# Skip param validations for ocfp as it provides these via its reference architecture
	if ($self->want_feature('cf-route-registrar') && !$self->want_feature('ocfp')) {
		push @errors, "Feature 'cf-route-registrar' requires params.cf_domain to be defined"
			unless $self->env->lookup('params.cf_domain');
	}

	# cf-haproxy-ca hands the broker the CF deployment's self-signed haproxy
	# CA for the API connection that cf-integration sets up, so it is
	# meaningless without that connection.
	if ($self->want_feature('cf-haproxy-ca')
	    && !$self->want_feature('cf-integration') && !$self->want_feature('ocfp')) {
		push @errors, "Feature 'cf-haproxy-ca' requires the 'cf-integration' feature ".
			"(or 'ocfp', which implies it): it hands the broker the CF deployment's ".
			"self-signed haproxy CA for the CF API connection that cf-integration configures";
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
	return $feature =~ /^(rabbitmq|redis|valkey|postgresql|mariadb|kubernetes)$/;
}
# }}}

# is_addon_feature - Check if feature is addon-related {{{2
sub is_addon_feature {
	my ($self, $feature) = @_;
	return $feature =~ /^(broker-tls|shield-backups|shield-agent|redis-tls|redis-dual-mode|valkey-tls|valkey-dual-mode|rabbitmq-tls|rabbitmq-dual-mode|rabbitmq-dashboard-registration|rabbitmq-autoscale|cf-route-registrar|cf-integration|cf-haproxy-ca)$/;
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
	elsif ($feature eq 'valkey-tls') {
		$self->add_files("manifests/forges/valkey-tls.yml");
	}
	elsif ($feature eq 'valkey-dual-mode') {
		$self->add_files("manifests/forges/valkey-dual-mode.yml");
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
	elsif ($feature eq 'cf-haproxy-ca') {
		# Generated in apply_post_processing so that it always merges after
		# ocfp/cf-integration.yml, whatever order the features were listed in.
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

	# Hand the broker the CF deployment's self-signed haproxy CA. Only
	# environments that name the feature get it.
	if ($self->want_feature("cf-haproxy-ca")) {
		$self->add_files($self->_generate_cf_haproxy_ca_overlay());
	}
}

# }}}

# _generate_cf_haproxy_ca_overlay - Point params.cf_cacert at the CF haproxy CA in vault {{{1
#
# Genesis generates the cf kit's self-signed haproxy certificates in vault
# under the CF deployment's secrets base and entombs into CredHub only what
# the CF manifest references; the haproxy job never references the CA, so
# the CA exists only in vault, as <vault_base>/haproxy_ca:certificate. The
# CF deployment records its vault_base in its exodus data, so read it from
# there rather than assuming the vault layout. Genesis entombs the resulting
# vault reference into this deployment's own CredHub scope at deploy time.
sub _generate_cf_haproxy_ca_overlay {
	my ($self) = @_;
	my $env = $self->env;
	my $cf_slug = $env->name.'/cf';

	my $vault_base = $env->exodus_lookup('vault_base', undef, $cf_slug);
	bail(
		"Feature 'cf-haproxy-ca' needs the exodus record of the #C{%s-cf} deployment ".
		"at #C{%s%s} to carry #C{vault_base}, which is where its self-signed haproxy ".
		"CA lives. Deploy that Cloud Foundry first, or set params.cf_cacert to the ".
		"CA certificate yourself.",
		$env->name, $env->exodus_mount, $cf_slug
	) unless defined($vault_base) && $vault_base =~ /\S/;

	$vault_base =~ s{^/+}{};
	$vault_base =~ s{/+$}{};

	my $file = 'ocfp/dynamic/cf-haproxy-ca.yml';
	my $abs_file = $self->kit->path($file);
	mkdir_or_fail(dirname($abs_file));
	mkfile_or_fail($abs_file, <<EOY);
---
# Generated by hooks/blueprint.pm for the cf-haproxy-ca feature: the CF
# deployment's self-signed haproxy CA, read from the vault path its exodus
# record names. An environment file may set params.cf_cacert to a PEM bundle
# instead, which wins over this value.
params:
  cf_cacert: (( vault "$vault_base/haproxy_ca:certificate" ))
EOY

	return $file;
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
		push @errors, "You have not activated any Blacksmith Forges. Please specify at least one of: rabbitmq, redis, valkey, postgresql, mariadb, kubernetes.";
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
