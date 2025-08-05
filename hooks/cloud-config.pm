package Genesis::Hook::CloudConfig::Blacksmith;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::CloudConfig);

use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;

use Genesis qw//;
use JSON::PP;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}

sub perform {
  my ($self) = @_;
  return 1 if $self->completed;

  my $iaas = $self->env->iaas;

  my $config = $self->build_cloud_config(
		{
			'networks' => [
				$self->network_definition('blacksmith',
					strategy => 'ocfp',
					dynamic_subnets => {
						subnets => ['ocfp-0'],
						allocation => {
							size => 1,
              statics => 0,
            },
            cloud_properties_for_iaas => {
              openstack => {
                'net_id' => $self->network_reference('id'),
                'security_groups' => ['default']
              },
              aws => {
                'subnet' => $self->subnet_reference('id'),
                'security_groups' => scalar $self->env->lookup('aws_default_sgs', ['default']),
              },
              azure => {
                'security_group' => scalar $self->env->lookup('azure_default_sg', 'default'),
              },
              google => {},
              vsphere => {},
              stackit => {
                'net_id' => $self->network_reference('id'),
                'security_groups' => scalar $self->env->lookup('stackit_default_security_groups', ['default'])
              }
            }
					}
        )
      ],
      'vm_types' => [
        $self->vm_type_definition('blacksmith',
          cloud_properties_for_iaas => {
            openstack => {
              'instance_type' => $self->for_scale({
                  dev => 'g1a.4d',
                  prod => 'g1a.8d'
                }, 'g1a.4d'),
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 32 # in gigabytes
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.medium',
                  prod => 'm6i.large'
                }, 't3.medium'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 16384
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
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
            stackit => {
              'instance_type' => $self->for_scale({
                  dev => 'g1a.4d',
                  prod => 'g1a.8d'
                }, 'g1a.4d'),
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 32
              },
            },
          },
        ),
        # Redis VM Types
        $self->vm_type_definition('redis-small',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.4d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 16
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.medium',
                  prod => 'c6i.large'
                }, 't3.medium'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 8192
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        $self->vm_type_definition('redis-medium',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.4d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 32
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.medium',
                  prod => 'c6i.xlarge'
                }, 't3.medium'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 16384
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        $self->vm_type_definition('redis-large',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.8d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 64
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.large',
                  prod => 'c6i.2xlarge'
                }, 't3.large'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 32768
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        # RabbitMQ VM Types
        $self->vm_type_definition('rabbitmq-small',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.4d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 16
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.small',
                  prod => 'c6i.large'
                }, 't3.small'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 8192
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        $self->vm_type_definition('rabbitmq-medium',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.4d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 32
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.medium',
                  prod => 'c6i.xlarge'
                }, 't3.medium'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 8192
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        $self->vm_type_definition('rabbitmq-large',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.8d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 64
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.large',
                  prod => 'c6i.2xlarge'
                }, 't3.large'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 16384
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        # PostgreSQL VM Types
        $self->vm_type_definition('postgres-small',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.4d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 16
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.small',
                  prod => 'c6i.large'
                }, 't3.small'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 8192
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        $self->vm_type_definition('postgres-medium',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.4d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 32
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.medium',
                  prod => 'c6i.xlarge'
                }, 't3.medium'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 8192
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
        $self->vm_type_definition('postgres-large',
          cloud_properties_for_iaas => {
            stackit => {
              'instance_type' => 'g1a.8d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => {
                'size' => 64
              },
            },
            aws => {
              'instance_type' => $self->for_scale({
                  dev => 't3.large',
                  prod => 'c6i.2xlarge'
                }, 't3.large'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({
                    dev => 4096,
                    prod => 8192
                  }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE
              },
              'metadata_options' => {
                'http_tokens' => 'required'
              },
            },
          },
        ),
      ],
      'disk_types' => [
        $self->disk_type_definition('blacksmith',
          common => {
            disk_size => $self->for_scale({
                dev => 16384, # 16 GB in MB
                prod => 65536, # 64 GB in MB
              }, 16384),
          },
          cloud_properties_for_iaas => {
            openstack => {
              'type' => 'storage_premium_perf6',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
            azure => {
              'storage_account_type' => 'Premium_LRS',
            },
            google => {
              'type' => 'pd-ssd',
            },
            vsphere => {},
            stackit => {},
          },
        ),
        # Redis Disk Types
        $self->disk_type_definition('redis-small',
          common => {
            disk_size => $self->for_scale({
                dev => 8192, # 8 GB in MB
                prod => 32768, # 32 GB in MB
              }, 8192),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf2',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        $self->disk_type_definition('redis-medium',
          common => {
            disk_size => $self->for_scale({
                dev => 16384, # 16 GB in MB
                prod => 65536, # 64 GB in MB
              }, 16384),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf4',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        $self->disk_type_definition('redis-large',
          common => {
            disk_size => $self->for_scale({
                dev => 32768, # 32 GB in MB
                prod => 131072, # 128 GB in MB
              }, 32768),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf6',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        # RabbitMQ Disk Types
        $self->disk_type_definition('rabbitmq-small',
          common => {
            disk_size => $self->for_scale({
                dev => 8192, # 8 GB in MB
                prod => 32768, # 32 GB in MB
              }, 8192),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf2',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        $self->disk_type_definition('rabbitmq-medium',
          common => {
            disk_size => $self->for_scale({
                dev => 16384, # 16 GB in MB
                prod => 65536, # 64 GB in MB
              }, 16384),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf4',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        $self->disk_type_definition('rabbitmq-large',
          common => {
            disk_size => $self->for_scale({
                dev => 32768, # 32 GB in MB
                prod => 131072, # 128 GB in MB
              }, 32768),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf6',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        # PostgreSQL Disk Types
        $self->disk_type_definition('postgres-small',
          common => {
            disk_size => $self->for_scale({
                dev => 8192, # 8 GB in MB
                prod => 32768, # 32 GB in MB
              }, 8192),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf2',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        $self->disk_type_definition('postgres-medium',
          common => {
            disk_size => $self->for_scale({
                dev => 16384, # 16 GB in MB
                prod => 65536, # 64 GB in MB
              }, 16384),
          },
          cloud_properties_for_iaas => {
            stackit => {
              'type' => 'storage_premium_perf4',
            },
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
          },
        ),
        $self->disk_type_definition('postgres-large',
          common => {
            disk_size => $self->for_scale({
                dev => 32768, # 32 GB in MB
                prod => 131072, # 128 GB in MB
              }, 32768),
          },
          cloud_properties_for_iaas => {
            aws => {
              'type' => 'gp3',
              'encrypted' => $self->TRUE,
            },
            stackit => {
              'type' => 'storage_premium_perf6',
            },
          },
        ),
      ],
    }
	);

  $self->done($config);

	return 1;

}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
