package Genesis::Hook::Addon::Blacksmith::Open v3.0.0;

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
    "Opens the Blacksmith Web Management Console in your browser.\n".
    "Works on macOS, Linux (with xdg-open), and Windows (WSL).\n".
    "Automatically handles authentication.";
}

# }}}

# perform - Execute the addon command {{{
sub perform {
  my ($self) = @_;
  my $env = $self->env;

  # Get connection details
  my $connection_info = $self->_get_connection_info();
  
  # Determine which open command to use
  my $open_cmd = $self->_get_open_command();
  unless ($open_cmd) {
    return $self->done(0);
  }
  
  # Build authenticated URL
  my $url = sprintf("%s://%s:%s@%s:%s",
    $connection_info->{scheme},
    $connection_info->{username},
    $connection_info->{password},
    $connection_info->{host},
    $connection_info->{port}
  );
  
  info("Opening Blacksmith Web Management Console...\n");
  info("  URL: #C{%s://%s:%s}\n", 
    $connection_info->{scheme}, 
    $connection_info->{host}, 
    $connection_info->{port}
  );
  info("  Username: #M{%s}\n", $connection_info->{username});
  info("\n");
  
  # Open the URL in the browser
  my ($out, $open_rc, $err) = run({stderr => 0}, '$1 "$2"', $open_cmd, $url);
  
  if ($open_rc != 0) {
    error("Failed to open browser: %s\n", $err || $out || 'Unknown error');
    error("\nYou can manually browse to:\n");
    error("  #B{%s}\n", $url);
    return $self->done(0);
  }
  
  info("#G{✓} Browser opened successfully.\n");
  return $self->done();
}

# }}}

# _get_open_command - Determine the appropriate open command {{{
sub _get_open_command {
  my ($self) = @_;
  
  # Try different open commands in order of preference
  my @commands = (
    { cmd => 'open', name => 'macOS open' },        # macOS
    { cmd => 'xdg-open', name => 'xdg-open' },      # Linux
    { cmd => 'gnome-open', name => 'gnome-open' },  # GNOME
    { cmd => 'kde-open', name => 'kde-open' },      # KDE
    { cmd => 'wslview', name => 'wslview' },        # WSL
  );
  
  for my $cmd_info (@commands) {
    my ($check, $rc) = run({stderr => 0}, 'command -v $1 >/dev/null 2>&1', $cmd_info->{cmd});
    if ($rc == 0) {
      return $cmd_info->{cmd};
    }
  }
  
  # No suitable command found
  error("\n#R{Error:} No suitable browser opening command found.\n");
  error("\nThis addon requires one of the following commands:\n");
  for my $cmd_info (@commands) {
    error("  - #C{%s} (%s)\n", $cmd_info->{cmd}, $cmd_info->{name});
  }
  error("\nYour system: %s\n", $^O);
  error("\nAlternatively, you can manually browse to the Blacksmith URL.\n");
  error("Run '#G{genesis do %s -- info}' to get the connection details.\n", $self->env->name);
  
  return undef;
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
    url => "$scheme://$host:$port",
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
