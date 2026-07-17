package Genesis::Hook::Features::Blacksmith v1.3.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Features);

use Genesis qw/bail/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;

  foreach my $feature (@{$self->{features}}) {
    # Pass through all features
    $self->add_feature($feature);

    # For OCFP feature, add additional features
    if ($feature eq 'ocfp') {
      $self->add_feature('broker-tls');
      $self->add_feature('external-bosh');
      $self->add_feature('cf-route-registrar');
      $self->add_feature('cf-integration');

      if ($self->has_feature('redis')) {
        $self->add_feature('redis-tls');
      }

      if ($self->has_feature('valkey')) {
        $self->add_feature('valkey-tls');
      }

      if ($self->has_feature('rabbitmq')) {
        $self->add_feature('rabbitmq-tls');
        $self->add_feature('rabbitmq-dashboard-registration');
      }
    }

    # Auto-include TLS features for dual-mode forges
    if ($feature eq 'rabbitmq-dual-mode') {
      $self->add_feature('rabbitmq-tls');
    }

    if ($feature eq 'redis-dual-mode') {
      $self->add_feature('redis-tls');
    }

    if ($feature eq 'valkey-dual-mode') {
      $self->add_feature('valkey-tls');
    }
  }

  return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
