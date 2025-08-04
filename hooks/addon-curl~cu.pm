package Genesis::Hook::Addon::Blacksmith::Curl v3.0.0;

use v5.20; # Genesis min perl version is 5.20
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);

use Genesis qw/bail info warning error run/;

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
    "Issues raw HTTP requests (via curl) against the Blacksmith Broker.\n".
    "Authentication is handled automatically.\n".
    "Usage: curl <path> [curl options...]\n".
    "Example: curl /v2/catalog -v";
}

# }}}

# perform - Execute the addon command {{{
sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Validate curl is available
  unless ($self->_check_curl_availability()) {
    return $self->done(0);
  }

  # Validate arguments
  unless ($self->_validate_arguments()) {
    return $self->done(0);
  }

  # Get connection details
  my $connection_info = $self->_get_connection_info();
  
  # Get the path from args
  my $path = shift @{$self->{args}};
  
  # Ensure path starts with /
  $path = "/$path" unless $path =~ m{^/};
  
  info("Executing curl request to #C{%s%s}...\n", $connection_info->{url}, $path);
  
  # Execute curl with authentication
  my ($out, $rc, $err) = run(
    {interactive => 1},
    'curl -u "$1:$2" "$3$4" "$@"',
    $connection_info->{username}, 
    $connection_info->{password}, 
    $connection_info->{url}, 
    $path,
    @{$self->{args}}
  );
  
  if ($rc != 0) {
    error("\nCurl request failed: %s\n", $err || 'Unknown error');
    return $self->done(0);
  }

  return $self->done();
}

# }}}

# _check_curl_availability - Check if curl is installed {{{
sub _check_curl_availability {
  my ($self) = @_;
  
  my ($curl_check, $curl_rc) = run({stderr => 0}, 'command -v curl >/dev/null 2>&1');
  if ($curl_rc != 0) {
    error("\n#R{Error:} The 'curl' command is not installed.\n");
    error("Please install curl to use this addon.\n");
    error("  - macOS:  #G{brew install curl}\n");
    error("  - Ubuntu: #G{apt-get install curl}\n");
    error("  - CentOS: #G{yum install curl}\n");
    return 0;
  }
  
  return 1;
}

# }}}

# _validate_arguments - Validate command arguments {{{
sub _validate_arguments {
  my ($self) = @_;
  
  if (!$self->{args}[0]) {
    error("\n#R{Error:} No path provided.\n\n");
    info("#Bu{Usage:}\n");
    info("  #G{genesis do %s -- curl <path> [curl options...]}\n\n", $self->env->name);
    info("#Bu{Examples:}\n");
    info("  # Get service catalog:\n");
    info("  #G{genesis do %s -- curl /v2/catalog}\n\n", $self->env->name);
    info("  # Get service instances with verbose output:\n");
    info("  #G{genesis do %s -- curl /v2/service_instances -v}\n\n", $self->env->name);
    info("  # Make a POST request:\n");
    info("  #G{genesis do %s -- curl /v2/service_instances -X POST -d '{...}'}\n\n", $self->env->name);
    return 0;
  }
  
  return 1;
}

# }}}

# _get_connection_info - Get Blacksmith connection information {{{
sub _get_connection_info {
  my ($self) = @_;
  my $env = $self->env;
  
  # Set up connection details
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

  my $blacksmith_url = "$scheme://$host:$port";
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
    url => $blacksmith_url,
    username => $blacksmith_username,
    password => $blacksmith_password,
    scheme => $scheme,
    host => $host,
    port => $port
  };
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
