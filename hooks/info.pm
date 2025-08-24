package Genesis::Hook::Info::Blacksmith v1.0.2;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

# Parent class inheritance
use parent qw(Genesis::Hook);

# Import required functions
use Genesis qw/bail info warning error run/;
use File::Basename qw/dirname/;

# Include common utilities
do(dirname(__FILE__) . '/_util.pm');

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

  # Gather deployment information
  my %info = $self->gather_deployment_info();
  
  # Display basic information header
  info("#Bu{Blacksmith Service Broker Information}\n");
  
  # Validate required data
  if (!$self->validate_required_data(\%info)) {
    warning("\nSome deployment information is missing. Please redeploy to generate the necessary data.\n");
  }

  # Display BOSH environment information
  #$self->display_bosh_environment();

  # Display Blacksmith internal BOSH director info
  #$self->display_blacksmith_bosh_info(\%info);

  # Display Blacksmith web UI information with connectivity check
  $self->display_blacksmith_ui_info(\%info);

  # Display Shield information if applicable
  #$self->display_shield_info(\%info) if $self->want_feature('shield-backups');

  # Display Blacksmith catalog
  #$self->display_blacksmith_catalog();

  return $self->done();
}

# }}}

# gather_deployment_info - Collect all deployment information {{{
sub gather_deployment_info {
  my ($self) = @_;
  my $env = $self->env;
  
  my %info = ();
  
  # Basic deployment information
  $info{ip} = $self->_get_blacksmith_ip();
  $info{fqdn} = $env->lookup('params.fqdn', '');
  $info{host} = $info{fqdn} || $info{ip};
  
  # Determine scheme and port based on TLS
  if ($self->want_feature('broker-tls')) {
    $info{port} = $env->lookup('params.blacksmith_tls_port', 443);
    $info{scheme} = 'https';
  } else {
    $info{port} = $env->lookup('params.blacksmith_port', 3000);
    $info{scheme} = 'http';
  }
  
  $info{blacksmith_url} = sprintf("%s://%s:%s", $info{scheme}, $info{host}, $info{port});
  $info{blacksmith_username} = 'blacksmith';
  
  # Vault information
  my $vault_path = $env->secrets_base;
  eval {
    $info{blacksmith_password} = $self->env->vault->get("${vault_path}broker:password");
  };
  if ($@) {
    warning("Failed to retrieve Blacksmith password from vault: %s", $@);
    $info{blacksmith_password} = '#R{<unavailable>}';
  }
  
  # BOSH director information from exodus
  my @bosh_fields = qw(bosh_address bosh_cacert bosh_username bosh_password);
  for my $field (@bosh_fields) {
    eval {
      $info{$field} = $env->exodus_lookup($field);
    };
    if ($@) {
      $info{$field} = undef;
    }
  }
  
  # Shield information if applicable
  if ($self->want_feature('shield-backups')) {
    my @shield_fields = qw(shield_url shield_username shield_password);
    for my $field (@shield_fields) {
      eval {
        $info{$field} = $env->exodus_lookup($field);
      };
      if ($@) {
        $info{$field} = undef;
      }
    }
  }
  
  return %info;
}

# }}}

# validate_required_data - Check if we have all required information {{{
sub validate_required_data {
  my ($self, $info) = @_;
  
  my @required = qw(ip bosh_address bosh_username bosh_password);
  my @missing;
  
  for my $field (@required) {
    push @missing, $field unless defined($info->{$field}) && $info->{$field};
  }
  
  if (@missing) {
    warning("Missing the following required data:\n%s", join("\n", map { "  - $_" } @missing));
    return 0;
  }
  
  return 1;
}

# }}}

# display_bosh_environment - Show BOSH environment information {{{
sub display_bosh_environment {
  my ($self) = @_;
  
  info("\n#Bu{BOSH Environment}\n");
  
  # Check if bosh command is available
  my ($bosh_check, $bosh_check_rc) = run({stderr => 0}, 'command -v bosh >/dev/null 2>&1');
  if ($bosh_check_rc != 0) {
    error("  The 'bosh' CLI is not installed or not in PATH.\n" .
          "  Please install the BOSH CLI to interact with BOSH.\n");
    return;
  }
  
  my ($out, $rc, $err) = run({stderr => 0}, "bosh -A env --tty 2>&1 | sed -e 's/^/  /'");
  if ($rc) {
    error("  Failed to execute bosh env command.\n" .
          "  This may indicate connectivity issues or authentication problems.\n" .
          "  Error: %s\n", $err || 'Unknown error');
  } else {
    info($out);
  }
}

# }}}

# display_blacksmith_bosh_info - Show Blacksmith's internal BOSH director {{{
sub display_blacksmith_bosh_info {
  my ($self, $info) = @_;
  
  info("\n#Bu{Blacksmith Internal BOSH Director}\n");
  info("  BOSH URL:  #C{%s}\n", $info->{bosh_address} || '#R{<unknown>}');
  info("  Username:  #M{%s}\n", $info->{bosh_username} || '#R{<unknown>}');
  info("  Password:  #G{%s}\n", $info->{bosh_password} || '#R{<unknown>}');
  
  if ($info->{bosh_cacert}) {
    info("\n  CA Certificate:\n");
    my @cert_lines = split /\n/, $info->{bosh_cacert};
    for my $line (@cert_lines) {
      info("  #c{%s}\n", $line);
    }
  }
}

# }}}

# display_blacksmith_ui_info - Show Blacksmith web UI with connectivity check {{{
sub display_blacksmith_ui_info {
  my ($self, $info) = @_;
  
  info("\n#Bu{Blacksmith Web Management UI}\n");
  info("  Web URL:   #C{%s}\n", $info->{blacksmith_url});
  info("  Username:  #M{%s}\n", $info->{blacksmith_username});
  info("  Password:  #G{%s}\n", $info->{blacksmith_password});
  
#  if ($info->{blacksmith_password} ne '#R{<unavailable>}') {
#    info("  Direct:    #B{%s://%s:%s@%s:%s}\n", 
#      $info->{scheme}, 
#      $info->{blacksmith_username}, 
#      $info->{blacksmith_password}, 
#      $info->{host}, 
#      $info->{port}
#    );
#  }
  
#  # Check connectivity to Blacksmith
#  info("\n  Checking Blacksmith API connectivity...\n");
#  
#  # Check DNS resolution
#  if ($info->{fqdn}) {
#    my ($dns_out, $dns_rc) = run({stderr => 0}, 'nslookup', $info->{fqdn});
#    if ($dns_rc != 0) {
#      warning("  DNS resolution failed for %s\n", $info->{fqdn});
#      warning("  Using IP address %s instead\n", $info->{ip});
#    }
#  }
#  
#  # Check API connectivity
#  my $check_url = $info->{blacksmith_url};
#  my ($curl_out, $curl_rc) = run(
#    {stderr => 0}, 
#    'curl', '-k', '-s', '-o', '/dev/null', '-w', '%{http_code}', 
#    '--connect-timeout', '5', $check_url
#  );
#  
#  if ($curl_rc == 0 && $curl_out =~ /^[23]\d\d$/) {
#    info("  #G{✓} API endpoint is reachable (HTTP %s)\n", $curl_out);
#  } else {
#    warning("  #R{✗} API endpoint is not reachable\n");
#    warning("  This may indicate:\n");
#    warning("    - Blacksmith is still starting up\n");
#    warning("    - Network/firewall configuration issues\n");
#    warning("    - The deployment needs to be completed\n");
#  }
}

# }}}

# display_shield_info - Show Shield backup information {{{
sub display_shield_info {
  my ($self, $info) = @_;
  
  return unless $info->{shield_url};
  
  info("\n#Bu{Shield Backup System}\n");
  info("  URL:       #C{%s}\n", $info->{shield_url} || '#R{<unknown>}');
  info("  Username:  #M{%s}\n", $info->{shield_username} || '#R{<unknown>}');
  info("  Password:  #G{%s}\n", $info->{shield_password} || '#R{<unknown>}');
  
  # Check Shield connectivity if we have a URL
  if ($info->{shield_url} && $info->{shield_url} ne '#R{<unknown>}') {
    info("\n  Checking Shield connectivity...\n");
    my ($shield_out, $shield_rc) = run(
      {stderr => 0},
      'curl', '-k', '-s', '-o', '/dev/null', '-w', '%{http_code}',
      '--connect-timeout', '5', $info->{shield_url}
    );
    
    if ($shield_rc == 0 && $shield_out =~ /^[23]\d\d$/) {
      info("  #G{✓} Shield is reachable (HTTP %s)\n", $shield_out);
    } else {
      warning("  #R{✗} Shield is not reachable\n");
    }
  }
}

# }}}

# display_blacksmith_catalog - Show available service catalog {{{
sub display_blacksmith_catalog {
  my ($self) = @_;
  
  info("\n#Bu{Blacksmith Service Catalog}\n");
  
  # Check if boss CLI is available
  my ($boss_check, $boss_rc) = run({stderr => 0}, 'command -v boss >/dev/null 2>&1');
  if ($boss_rc != 0) {
    info("  #Y{!} The 'boss' CLI is not installed.\n");
    info("  Install it from: #C{https://github.com/jhunt/boss}\n");
    info("  Once installed, you can query the catalog with:\n");
    info("    #G{boss catalog}\n");
    return;
  }
  
  info("  Retrieving catalog...\n");
  my ($catalog, $catalog_rc, $catalog_err) = run({stderr => 0}, 'boss catalog 2>&1');
  
  if ($catalog_rc != 0) {
    error("  Failed to retrieve catalog.\n");
    if ($catalog_err || $catalog) {
      error("  Error: %s\n", $catalog_err || $catalog);
    }
    info("\n  This may indicate:\n");
    info("    - BOSS_URL environment variable is not set\n");
    info("    - Blacksmith API is not accessible\n");
    info("    - Authentication issues\n");
    info("\n  Try setting BOSS_URL and credentials:\n");
    info("    #G{export BOSS_URL=%s}\n", $self->env->lookup('params.blacksmith_url', ''));
    info("    #G{export BOSS_USERNAME=blacksmith}\n");
    info("    #G{export BOSS_PASSWORD=<password>}\n");
  } else {
    # Format catalog output with proper indentation
    my @lines = split /\n/, $catalog;
    for my $line (@lines) {
      info("  %s\n", $line);
    }
  }
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
