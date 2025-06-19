package Genesis::Hook::PostDeploy::Blacksmith;

use v5.20;
use warnings; # Genesis min perl version is 5.20
use Genesis qw/info/;
# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::PostDeploy);
sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;

  # Base class has deploy_successful method to check if GENESIS_DEPLOY_RC == 0
  if ($self->deploy_successful) {
    info(
      "\n#M{$ENV{GENESIS_ENVIRONMENT}} Blacksmith Broker deployed!\n".
      "\nFor details about the deployment, run\n".
      "\t#G{$ENV{GENESIS_CALL_ENV} info}\n".
      "\nTo access the Blacksmith Web Management Console, run\n".
      "\t#G{$ENV{GENESIS_CALL_ENV} do -- visit}\n".
      "\nTo log into the Blacksmith BOSH director, (to troubleshoot service provisioning), run\n".
      "\t#G{$ENV{GENESIS_CALL_ENV} do -- bosh}\n".
    );
  }

  return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
