package Genesis::Hook::Addon::Blacksmith::Open;

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
    "Opens the Blacksmith Web Management Console in your browser.\n".
    "Only works on macOS and some Linux distributions that support the 'open' command.";
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

  my $blacksmith_username = 'blacksmith';
  my $blacksmith_password = $self->vault->get("$vault/broker:password");

  # Check if 'open' command is available
  my ($cmd_check, $rc) = run({stderr => '/dev/null'}, 'command -v open >/dev/null 2>&1');
  if ($rc != 0) {
    bail("The 'open' addon script only works on macOS and Linux with 'open' support, currently.");
  }

  # Open the URL in the browser
  my ($out, $open_rc) = run('open "$1"', "$scheme://$blacksmith_username:$blacksmith_password\@$host:$port");
  bail("Failed to open browser: %s", $out) if $open_rc != 0;

  return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
