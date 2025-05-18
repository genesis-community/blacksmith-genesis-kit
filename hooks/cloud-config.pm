#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::CloudConfig::Blacksmith v4.0.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::CloudConfig);

use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;

use Genesis qw//;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');
  return $obj;
}

sub perform {
  my ($self) = @_;
  return 1 if $self->completed;

  my $iaas = $self->env->iaas;

  my $config = $self->build_cloud_config({
      'networks' => [
        $self->network_definition('blacksmith', strategy => 'ocfp',
          dynamic_subnets => {
            allocation => {
              size => 0,
              statics => 0,
            },
            cloud_properties_for_iaas => {
              openstack => {
                'net_id' => $self->network_reference('id'),
                'security_groups' => ['default']
              },
              aws => {
                'security_groups' => $self->env->lookup('aws_default_sgs', ['default']),
              },
              azure => {
                'security_group' => $self->env->lookup('azure_default_sg', 'default'),
              },
              google => {},
              vsphere => {},
            },
          },
        )
      ],
      'vm_types' => [
        $self->vm_type_definition('blacksmith',
          cloud_properties_for_iaas => {
            openstack => {
              'instance_type' => $self->for_scale({
                  dev => 'm1.2',
                  prod => 'm1.3'
                }, 'm1.2'),
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 32 # in gigabytes
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.medium',
                  prod => 'm5.large'
                }, 't3.medium'),
              'ephemeral_disk' => {
                'size' => 32768, # 32GB
                'type' => 'gp2'
              },
            },
            azure => {
              'instance_type' => $self->for_scale({
                  dev => 'Standard_D2s_v3',
                  prod => 'Standard_D4s_v3'
                }, 'Standard_D2s_v3'),
            },
            google => {
              'machine_type' => $self->for_scale({
                  dev => 'n1-standard-2',
                  prod => 'n1-standard-4'
                }, 'n1-standard-2'),
              'root_disk_size_gb' => 32,
              'root_disk_type' => 'pd-ssd',
            },
            vsphere => {
              'cpu' => $self->for_scale({
                  dev => 2,
                  prod => 4
                }, 2),
              'ram' => $self->for_scale({
                  dev => 4096,
                  prod => 8192
                }, 4096),
              'disk' => 32768,
            },
          },
        ),
      ],
      'disk_types' => [
        $self->disk_type_definition('blacksmith',
          common => {
            disk_size => $self->for_scale({
                dev => gigabytes(64),
                prod => gigabytes(128)
              }, gigabytes(96)),
          },
          cloud_properties_for_iaas => {
            openstack => {
              'type' => 'storage_premium_perf6',
            },
            aws => {
              'type' => 'gp2',
            },
            azure => {
              'storage_account_type' => 'Premium_LRS',
            },
            google => {
              'type' => 'pd-ssd',
            },
            vsphere => {},
          },
        ),
      ],
    });

  $self->done($config);
}

1;
