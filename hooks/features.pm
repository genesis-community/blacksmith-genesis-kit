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

  # Pass every declared feature through BEFORE deciding what else to add.
  # The blocks below ask has_feature() about other entries in the same
  # list, and has_feature() only knows what add_feature() has already been
  # told - so while this ran inside the loop, the answers depended on the
  # order the operator happened to write the features in.
  #
  # 'ocfp' first is the convention in every OCFP environment file, and it
  # is the worst case: has_feature('redis'), ('valkey') and ('rabbitmq')
  # were all false at that point, so redis-tls, valkey-tls, rabbitmq-tls
  # and rabbitmq-dashboard-registration were silently dropped and the
  # forges deployed without TLS. Nothing warned; the manifest simply had
  # no tls block.
  $self->add_feature($_) foreach @{$self->{features}};

  foreach my $feature (@{$self->{features}}) {
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
