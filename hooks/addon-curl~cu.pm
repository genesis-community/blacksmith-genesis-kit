package Genesis::Hook::Addon::Blacksmith::Curl;

use v5.20;
use warnings; # Genesis min perl version is 5.20
use Genesis qw/bail info run/;
# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub cmd_details {
  return
    "Issues raw HTTP requests (via curl) against the Blacksmith Broker.\n".
    "Authentication is handled automatically.\n".
    "Usage: curl <path> [curl options...]\n".
    "Example: curl /v2/catalog -v";
}

sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Set up connection details
  my $vault = "$ENV{GENESIS_SECRETS_MOUNT}/$ENV{GENESIS_VAULT_PREFIX}";
  my $ip = $env->lookup('params.ip');
  my $fqdn = $env->lookup('params.fqdn');
  my $host = $fqdn ? $fqdn : $ip;

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
  my $blacksmith_password = $self->vault->get("$vault/broker:password");

  # Check if curl is installed
  my ($curl_check, $curl_rc) = run({stderr => '/dev/null'}, 'command -v curl >/dev/null 2>&1');
  if ($curl_rc != 0) {
    info("  !!! install curl cli first!");
    return $self->done(0);
  }

  # Get the path from args
  if (!$self->{args}[0]) {
    bail("No path provided. Usage: curl <path> [curl options...]");
  }

  my $path = shift @{$self->{args}};

  # Execute curl with authentication
  my ($out, $rc, $err) = run(
    {interactive => 1},
    'curl -u "$1:$2" "$3$4" "$@"',
    $blacksmith_username, $blacksmith_password, $blacksmith_url, $path,
    @{$self->{args}}
  );
  bail("Failed to run curl command: %s", $err) if $rc != 0;

  return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
