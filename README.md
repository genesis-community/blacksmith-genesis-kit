blacksmith Genesis Kit
=================

The Blacksmith Genesis Kit give you the ability to deploy
on-demand services in Cloud Foundry, using the Open Service Broker
API.  These services will be backed by real VMs, running under the
watchful eye of a dedicated BOSH director.

For more information on Blacksmith itself, check out the
[Blacksmith Project Page on Github][blacksmith] and the
[Blacksmith BOSH Release Docs][blacksmith-bosh].

Quick Start
-----------

To use it, you don't even need to clone this repository! Just run
the following (using Genesis v2):

```
# create a blacksmith-deployments repo using the latest version of the blacksmith kit
genesis init --kit blacksmith

# create a blacksmith-deployments repo using v1.0.0 of the blacksmith kit
genesis init --kit blacksmith/1.0.0

# create a my-blacksmith-configs repo using the latest version of the blacksmith kit
genesis init --kit blacksmith -d my-blacksmith-configs
```

Once created, refer to the deployment repo's README for information on creating
new environments.

Feature Flags
-------------

Blacksmith Features come in two flavors: IaaS support and Forges.

### IaaS Feature: `vsphere`

This is currently the only supported IaaS.  If you want to run
Blacksmith, under Genesis, on other infrastructures, please let us
know by opening a [Github Issue][1].

The `vsphere` feature adds the vSphere CPI to the Blacksmith Bosh
director, and configures it to point to your VMWare environment.

The following parameters exist:

- **vsphere_ip** - The IP address of your vCenter (VCSA) server
  that manages the vSphere environment that Blacksmith should
  deploy to.

- **vsphere_ephemeral_datastores** - A YAML list of data store
  names where the Blacksmith BOSH director will store ephemeral
  (operating systems) disks.

- **vsphere_persistent_datastores** - A YAML list of data store
  names where the Blacksmith BOSH director will store persistent
  (data) disks.

- **vsphere_clusters** - A YAML list of vSphere cluster names
  where Blacksmith will deploy service VMs.

- **vsphere_datacenter** - The name of the vSphere data center
  where Blacksmith will deploy things.  The clusters listed in
  `vsphere_clusters` must exist within `vsphere_datacenter`.

### Forge: `postgresql`

The `postgresql` feature activates the [Blacksmith PostgreSQL
Forge][postgresql-forge] so that this Blacksmith can deploy
standalone and clustered PostgreSQL database services.

The following parameters exist:

- **postgresql_plans** - A YAML fragment that contains the set of
  Cloud Foundry service plans to offer, insofar as PostgreSQL is
  concerned.  For full details, you'll want to refer to the
  [forge documentation][postgresql-forge].

### Forge: `rabbitmq`

The `rabbitmq` feature activates the [Blacksmith RabbitMQ
Forge][rabbitmq-forge] so that this Blacksmith can deploy
RabbitMQ messaging clusters.

The following parameters exist:

- **rabbitmq_plans** - A YAML fragment that contains the set of
  Cloud Foundry service plans to offer, insofar as RabbitMQ is
  concerned.  For full details, you'll want to refer to the
  [forge documentation][rabbitmq-forge].

### Forge: `redis`

The `redis` feature activates the [Blacksmith Redis
Forge][redis-forge] so that this Blacksmith can deploy
standalone and clustered Redis instances that are either
persistent (for durable key-value storage) or not (caches).

- **redis_plans** - A YAML fragment that contains the set of Cloud
  Foundry service plans to offer, infosfar as Redis is concerned.
  For full details, you'll want to refer to the
  [forge documentation][redis-forge].

Params
------

Regardless of what forges you run, or what infrastructure you run
on, you'll probably want to configure the broker itself.  Here's
the parameters that let you do that:

### General Infrastructure Configuration

- **stemcell_os** - The operating system you want to deploy on.
  This defaults to `ubuntu-trusty`.

- **stemcell_version** - The version of the stemcell to deploy.
  This defaults to `latest`, which is usually what you want.

- **network** - The name of the `network` (per cloud-config) where
  the blacksmith broker will be deployed.  Defaults to `default`.

- **vm_type** - The name of the `vm_type` (per cloud-config) that
  will be used to deploy the blacksmith broker VM.  Defaults to
  `default`.

- **disk_size** - How big of a data disk to provide the Blacksmith
  broker, for persistent storage.  Defaults to `20480` (20G).

- **http_proxy** - (Optional) URL of an HTTP proxy to use for any
  outbound HTTP (non-TLS) communication.

- **https_proxy** - (Optional) URL of an HTTP proxy to use for any
  outbound HTTPS (TLS) communication.

- **no_proxy** - A list of IPs, FQDNs, partial domains, etc. to
  skip the proxy and connect to directly.  This has no effect if
  the `http_proxy` and `https_proxy` are not set.

### Broker Deployment

- **ip** - The static IP address of to deploy the Blacksmith
  broker to.  This must exist within the static range of the
  `network` 

- **blacksmith_debug** - Whether or not to enable Blacksmith
  debug logging.  Defaults to `false`, but you can set it to
  `true` if you really like log output.

- **blacksmith_port** - The TCP port that Blacksmith will bind to
  This defaults to `3000`.

- **blacksmith_env** - An identifying string that will be used to
  differentiate Blacksmith brokers in their management UIs.
  Defaults to empty, but you probably want to set this.

### Blacksmith Broker Deployment

- **cloud_config** - A YAML chunk that defines an entire BOSH v2
  cloud-config that Blacksmith will deploy to its internal BOSH
  director.

- **releases** - A list of releases that Blacksmith should upload
  to its internal BOSH director, for use by service deployments.
  Each entry must include `name`, `version`, `url` and `sha1`
  keys.  Most of the time, the Forge manifests will set these
  themselves, but sometimes you need to do your own thing.

- **stemcells** - A list of stemcells that Blacksmith should
  upload to its internal BOSH director, for use by service
  deployments.  You will almost always have to specify these,
  since Forge manifests will rarely be in a position to anticipate
  your IaaS choices.



[1]: https://github.com/genesis-community/blacksmith-genesis-kit/issues

[blacksmith]: https://github.com/cloudfoundry-community/blacksmith
[blacksmith-bosh]: https://github.com/cloudfoundry-community/blacksmith-boshrelease

[postgresql-forge]: https://github.com/blacksmith-community/postgresql-forge-boshrelease
[rabbitmq-forge]:   https://github.com/blacksmith-community/rabbitmq-forge-boshrelease
[redis-forge]:      https://github.com/blacksmith-community/redis-forge-boshrelease
