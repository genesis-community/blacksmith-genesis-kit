package Genesis::Hook::CloudConfig::Blacksmith v1.3.0;

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
  my $config = $self->build_cloud_config({
      'azs' => [
        # The valkey-forge (and other) release job plans hardcode a bare
        # "z1" az default (`meta.azs || [z1]`). Live directors only define
        # env-namespaced azs (eg <env>-z1/-z2/-z3) via the director's own
        # config, never a plain "z1" - so the default plan can't resolve
        # without this. Provided as a raw entry, bypassing az naming
        # helpers, mirroring the vm_type "default" raw-hashref approach
        # below. If a future base/named config also defines a plain "z1",
        # BOSH's cloud-config merge applies to whichever named configs are
        # attached to the deployment - this entry is not deduplicated
        # against other named configs, so watch for a collision there.
        ($self->want_feature('valkey') ?
          ({
            name => 'z1',
            ($self->cpi_enabled ? (cpi => $self->cpi_name) : ()),
            cloud_properties => {},
          }) : ()
        ),
      ],
			'networks' => [
				$self->network_definition('blacksmith',
					strategy => 'ocfp',
					dynamic_subnets => {
						subnets => ['ocfp-1'],
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
                'subnet' => $self->subnet_reference('id'),
                'security_groups' => $self->get_network_security_groups(),
              },
              azure => {
                'security_group' => scalar $self->env->lookup('azure_default_sg', 'default'),
              },
              google => {},
              vsphere => {},
              stackit => {
                'net_id' => $self->network_reference('id'),
                'security_groups' => scalar $self->env->lookup('stackit_default_security_groups', ['default'])
              },
              pve => {
                'bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
              }
            }
					}
        ),
        # The valkey-forge release job hardcodes this bare network name as
        # its default (see valkey-blacksmith-plans job's standalone/cluster
        # plan templates: `meta.net || "valkey-service"`), so it must exist
        # unprefixed for the default plan to resolve without a manually
        # uploaded supplemental cloud config. name_prefix => '' opts out of
        # the usual env-namespaced naming that network_definition applies.
        ($self->want_feature('valkey') ?
          (map {
            my $net = $_;
            # The subnet inherits an env-namespaced az (eg <env>-z2) from
            # the ocfp subnet data, but the default plans deploy instance
            # groups into the bare "z1" az defined above - BOSH requires
            # the instance group az to match an az of its network's
            # subnets, so realign the generated subnets to "z1".
            $_->{az} = 'z1' for @{$net->{subnets} // []};
            $net;
          } $self->network_definition('valkey-service',
            strategy => 'ocfp',
            name_prefix => '',
            dynamic_subnets => {
              subnets => ['ocfp-1'],
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
                  'subnet' => $self->subnet_reference('id'),
                  'security_groups' => $self->get_network_security_groups(),
                },
                azure => {
                  'security_group' => scalar $self->env->lookup('azure_default_sg', 'default'),
                },
                google => {},
                vsphere => {},
                stackit => {
                  'net_id' => $self->network_reference('id'),
                  'security_groups' => scalar $self->env->lookup('stackit_default_security_groups', ['default'])
                },
                pve => {
                  'bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
                }
              }
            }
          )) : ()
        ),
      ],
      'vm_types' => [
        # The valkey/redis/rabbitmq/postgresql forge releases all hardcode
        # this bare vm_type name as their default plan's sizing (see each
        # forge's *-blacksmith-plans job templates). Provided as a raw
        # cloud-config entry (bypassing vm_type_definition's automatic
        # env-namespaced naming) so the default plan resolves without an
        # operator having to hand-upload a supplemental cloud config.
        {
          name => 'default',
          cloud_properties => scalar($self->_cloud_properties_for_iaas(
            openstack => {
              'instance_type' => $self->for_scale({ dev => 'g1a.2d', prod => 'g1a.4d' }, 'g1a.2d'),
              'boot_from_volume' => $self->TRUE,
              'root_disk' => { 'size' => 16 },
            },
            aws => {
              'instance_type' => $self->for_scale({ dev => 't3.small', prod => 'c6i.large' }, 't3.small'),
              'ephemeral_disk' => {
                'size' => $self->for_scale({ dev => 4096, prod => 8192 }, 4096),
                'type' => 'gp3',
                'encrypted' => $self->TRUE,
              },
              'metadata_options' => { 'http_tokens' => 'required' },
            },
            stackit => {
              'instance_type' => 'g1a.2d',
              'boot_from_volume' => $self->TRUE,
              'root_disk' => { 'size' => 16 },
            },
            pve => {
              'cpu'            => scalar($self->env->lookup('bosh-configs.cpi.pve_service_default_cpu',  $self->for_scale({ dev => 1, prod => 2 }, 1))),
              'ram'            => scalar($self->env->lookup('bosh-configs.cpi.pve_service_default_ram',  $self->for_scale({ dev => 2048, prod => 4096 }, 2048))),
              'disk'           => scalar($self->env->lookup('bosh-configs.cpi.pve_service_default_disk', $self->for_scale({ dev => 16384, prod => 32768 }, 16384))),
              'network_bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
            },
          )),
        },
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
                    dev => 8192,
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
            pve => {
              'cpu'            => scalar($self->env->lookup('bosh-configs.cpi.pve_blacksmith_cpu',  $self->for_scale({ dev => 2, prod => 4 }, 2))),
              'ram'            => scalar($self->env->lookup('bosh-configs.cpi.pve_blacksmith_ram',  $self->for_scale({ dev => 4096, prod => 8192 }, 4096))),
              'disk'           => scalar($self->env->lookup('bosh-configs.cpi.pve_blacksmith_disk', $self->for_scale({ dev => 32768, prod => 65536 }, 32768))),
              'network_bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
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
            pve => {
              'cpu'            => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_small_cpu',  $self->for_scale({ dev => 1, prod => 2 }, 1))),
              'ram'            => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_small_ram',  $self->for_scale({ dev => 2048, prod => 4096 }, 2048))),
              'disk'           => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_small_disk', $self->for_scale({ dev => 16384, prod => 32768 }, 16384))),
              'network_bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
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
            pve => {
              'cpu'            => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_medium_cpu',  $self->for_scale({ dev => 2, prod => 4 }, 2))),
              'ram'            => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_medium_ram',  $self->for_scale({ dev => 4096, prod => 8192 }, 4096))),
              'disk'           => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_medium_disk', $self->for_scale({ dev => 32768, prod => 65536 }, 32768))),
              'network_bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
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
            pve => {
              'cpu'            => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_large_cpu',  $self->for_scale({ dev => 2, prod => 8 }, 2))),
              'ram'            => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_large_ram',  $self->for_scale({ dev => 8192, prod => 16384 }, 8192))),
              'disk'           => scalar($self->env->lookup('bosh-configs.cpi.pve_postgres_large_disk', $self->for_scale({ dev => 65536, prod => 131072 }, 65536))),
              'network_bridge' => scalar($self->env->lookup('bosh-configs.cpi.pve_network_bridge', 'lvnet001')),
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
            pve => {
              'storage'     => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_storage', 'zfs-1')),
              'disk_format' => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_format', 'raw')),
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
            pve => {
              'storage'     => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_storage', 'zfs-1')),
              'disk_format' => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_format', 'raw')),
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
            pve => {
              'storage'     => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_storage', 'zfs-1')),
              'disk_format' => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_format', 'raw')),
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
            pve => {
              'storage'     => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_storage', 'zfs-1')),
              'disk_format' => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_format', 'raw')),
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
