# Blacksmith Genesis Kit Manual

The **Blacksmith Genesis Kit** deploys a Blacksmith On-Demand
Services Broker for Cloud Foundry.  Blacksmith uses BOSH to deploy
new data services instances on behalf of end users.

# Base Parameters

- `ip` - The static IP address to deploy the Blacksmith broker
  to.  This must exist within the static range of the `network`.

## Sizing and Deployment Parameters

- `network` - The name of the `network` (per cloud-config) where
  the blacksmith broker will be deployed.  Defaults to `blacksmith`.

- `stemcell_os` - The operating system you want to deploy the
  Blacksmith service broker itself on.  This defaults to
  `ubuntu-xenial`.

- `stemcell_version` - The version of the stemcell to deploy.
  Defaults to `97.latest`, which is usually what you want, since
  this kit uses precompiled BOSH director releases that only work
  on the 97.x ubuntu-xenial series.

- `vm_type` - The name of the `vm_type` (per cloud-config) that
  will be used to deploy the blacksmith broker VM.  Defaults to
  `blacksmith`.

- `disk_size` - How big of a data disk to provide the Blacksmith
  broker, for persistent storage.  Defaults to `20480` (20G).

## Blacksmith Broker Parameters

- `blacksmith_debug` - Whether or not to enable Blacksmith
  debug logging.  Defaults to `false`, but you can set it to
  `true` if you really like log output.

- `blacksmith_port` - The TCP port that Blacksmith will bind to
  This defaults to `3000`.

- `blacksmith_env` - An identifying string that will be used to
  differentiate Blacksmith brokers in their management UIs.
  Defaults to empty, but you probably want to set this.

### Blacksmith (Internal) BOSH Director Parameters

- `cloud_config` - A YAML chunk that defines an entire BOSH v2
  cloud-config that Blacksmith will deploy to its internal BOSH
  director.

- `releases` - A list of releases that Blacksmith should upload
  to its internal BOSH director, for use by service deployments.
  Each entry must include `name`, `version`, `url` and `sha1`
  keys.  Most of the time, the Forge manifests will set these
  themselves, but sometimes you need to do your own thing.

- `stemcells` - A list of stemcells that Blacksmith should
  upload to its internal BOSH director, for use by service
  deployments.  You will almost always have to specify these,
  since Forge manifests will rarely be in a position to anticipate
  your IaaS choices.

## HTTP(S) Proxy Parameters

- `http_proxy` - (Optional) URL of an HTTP proxy to use for any
  outbound HTTP (non-TLS) communication.

- `https_proxy` - (Optional) URL of an HTTP proxy to use for any
  outbound HTTPS (TLS) communication.

- `no_proxy` - A list of IPs, FQDNs, partial domains, etc. to
  skip the proxy and connect to directly.  This has no effect if
  the `http_proxy` and `https_proxy` are not set.

# Features

- `vsphere` (IaaS) - Deploy the on-demand services to a VMWare
  vSphere hypervisor cluster.  You will need to provide all of the
  information Blacksmith needs to contact the vCenter API for VM
  orchestration purposes.

  Activating this feature also activates the following parameters:

  - `vsphere_ip` - The IP address of your vCenter (VCSA) server
    that manages the vSphere environment to deploy to.

  - `vsphere_ephemeral_datastores` - A YAML list of data store
    names where the Blacksmith BOSH director will store ephemeral
    (operating systems) disks.

  - `vsphere_persistent_datastores` - A YAML list of data store
    names where the Blacksmith BOSH director will store persistent
    (data) disks.

  - `vsphere_datacenter` - The name of the vSphere data center
    where Blacksmith will deploy things.  The clusters listed in
    `vsphere_clusters` must exist within this data center.

  - `vsphere_clusters` - A YAML list of vSphere cluster names
    where Blacksmith will deploy service VMs.

- `postgresql` (Blacksmit Forge) - Enables the Blacksmith Service
  Broker to deploy PostgreSQL database services.

  Activating this feature also activates the following parameters:

  - `postgresql_plans` - A YAML fragment that contains the set of
     Cloud Foundry PostgreSQL service plans to offer.

  - `postgresql_service_name` - The name of the service, to be
    shown in the services marketplace.

    Defaults to `postgresql`.

  - `postgresql_service_id` - A globally unique (internal)
    identifier for this service.

    Defaults to `postgresql`.

  - `postgresql_service_description` - A long-form description of
    the service, for use in both console and web-based UIs.

    Defaults to `A dedicated PostgreSQL instance, deployed
    on-demand.`

  - `postgresql_service_tags` - The list of tags to apply to all
    new instances of this service.

    Defaults to `blacksmith`, `postgresql`, and `dedicated`.  If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `postgresql_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits.  `0` (the default) imposes no global
    limit.

- `rabbitmq` (Blacksmith Forge) - Enables the Blacksmith Service
  Broker to deploy RabbitMQ messaging clusters.

  Activating this feature also activates the following parameters:

  - `rabbitmq_plans` - A YAML fragment that contains the set of
     Cloud Foundry RabbitMQ service plans to offer.

  - `rabbitmq_service_name` - The name of the service, to be
    shown in the services marketplace.

    Defaults to `rabbitmq`.

  - `rabbitmq_service_id` - A globally unique (internal)
    identifier for this service.

    Defaults to `rabbitmq`.

  - `rabbitmq_service_description` - A long-form description of
    the service, for use in both console and web-based UIs.

    Defaults to `A dedicated RabbitMQ instance, deployed
    on-demand.`

  - `rabbitmq_service_tags` - The list of tags to apply to all
    new instances of this service.

    Defaults to `blacksmith`, `rabbitmq`, and `dedicated`.  If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `rabbitmq_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits.  `0` (the default) imposes no global
    limit.

- `redis` (Blacksmith Forge) - Enables the Blacksmith Service
  Broker to deploy Redis key-value instances that are either
  persistent (for durable key-value storage) or not (caches).

  Activating this feature also activates the following parameters:

  - `redis_plans` - A YAML fragment that contains the set of
     Cloud Foundry Redis service plans to offer.

  - `redis_service_name` - The name of the service, to be
    shown in the services marketplace.

    Defaults to `redis`.

  - `redis_service_id` - A globally unique (internal)
    identifier for this service.

    Defaults to `redis`.

  - `redis_service_description` - A long-form description of
    the service, for use in both console and web-based UIs.

    Defaults to `A dedicated Redis instance, deployed
    on-demand.`

  - `redis_service_tags` - The list of tags to apply to all
    new instances of this service.

    Defaults to `blacksmith`, `redis`, and `dedicated`.  If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `redis_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits.  `0` (the default) imposes no global
    limit.

- `mariadb` (Blacksmith Forge) - Enables the Blacksmith Service
  Broker to deploy MariaDB / MySQL database services.

  This forge is currently experimental, and only supports
  standalone, single-node service deployments.

  Activating this feature also activates the following parameters:

  - `mariadb_plans` - A YAML fragment that contains the set of
     Cloud Foundry MariaDB / MySQL service plans to offer.

  - `mariadb_service_name` - The name of the service, to be
    shown in the services marketplace.

    Defaults to `mariadb`.

  - `mariadb_service_id` - A globally unique (internal)
    identifier for this service.

    Defaults to `mariadb`.

  - `mariadb_service_description` - A long-form description of
    the service, for use in both console and web-based UIs.

    Defaults to `A dedicated MariaDB instance, deployed
    on-demand.`

  - `mariadb_service_tags` - The list of tags to apply to all
    new instances of this service.

    Defaults to `blacksmith`, `mariadb`, and `dedicated`.  If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `mariadb_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits.  `0` (the default) imposes no global
    limit.


# Cloud Configuration

By default, Blacksmith uses the following VM types/networks/disk
pools from your cloud config. Feel free to override them in your
environment, if you would rather they use entities already
existing in your cloud config:

```
params:
  network:   blacksmith
  vm_type:   blacksmith
```

# Available Addons

- `visit` - Opens the Blacksmith Web Management Console in your
  browser.  This only works on macOS.

  This web interface provides an at-a-glance summary of all the
  salient bits of the Blacksmith broker deployment, the service
  catalog, quotas, and deployed service instances.

  This interface is protected by HTTP basic authentication, and
  this addon takes that into account, without bothering you.

- `register` - Register this Blacksmith Broker with a Cloud
  Foundry instance (deployed by Genesis).  Optionally takes the
  name of the CF environment to register with.

- `bosh` - Sets up a local alias for the Blacksmith (Internal)
  BOSH director, retrieves the X.509 CA Certificate and BOSH admin
  credentials, and authenticates to it.

  After this runs, you will be able to use the BOSH CLI, unaided,
  to interact with the Blacksmith BOSH director, for
  troubleshooting and diagnostics.

- `eden` - Runs `eden`, a command-line utility for interacting
  directly with Blacksmith via the Open Service Broker API,
  without needing a Cloud Foundry instance.

  This requires that you have `eden` already installed.  You can
  get `eden` from https://github.com/starkandwayne/eden/releases

- `curl` - Run arbitrary HTTP requests against the Blacksmith
  Broker and its API.  This is very useful for troubleshooting
  weird Blacksmith issues.  The `/b/status` and `/b/catalog`
  endpoints are useful.

# Examples

Deploying Blacksmith with a vSphere director:

```
---
kit:
  name:    blacksmith
  version: 5.6.7
  features:
    - vsphere

params:
  env: acme-us-east-1-prod

  ip: 10.0.134.4

  # vSphere
  vsphere_ip:         10.0.0.254
  vsphere_datacenter: prod-esx-01
  vsphere_clusters:
    - cf1

  vsphere_ephemeral_datastores:
    - vol20
    - vol21
    - vol22
    - vol23

  vsphere_persistent_datastores:
    - san1
    - san3
```

Since Blacksmith has its own internal BOSH director, you need to
supply a cloud configuration, and stemcells.  Here's an example:

```
  cloud_config:
    azs:
      - name: z1
        cloud_properties:
          datacenters:
            - name: prod-esx-01
              clusters:
                - cf1: {}

    networks:
      - name: services
        type: manual
        subnets:
          - range: 10.254.0.0/16
            gateway: 10.254.0.1
            az: z1
            cloud_properties:
              name: VMNetwork

    vm_types:
      - name: small
        cloud_properties:
          cpu:  2
          ram:  2_048
          disk: 8_192

      - name: medium
        cloud_properties:
          cpu:   4
          ram:   8_192
          disk: 32_768

    compilation:
      workers: 3
      reuse_compilation_vms: true
      az: z1
      vm_type: small
      network: services
```

Example PostgreSQL service offering plans:

```
  postgresql_plans:
    standalone:
      type:    standalone
      vm_type: small
      network: services
      disk:    8_192
      limit:   10

    small-cluster:
      type:    cluster
      vm_type: medium
      network: services
      disk:    8_192
      limit:   3
```

# History

Version 0.2.0 was the first version to support Genesis 2.6 hooks
for addon scripts and `genesis info`.
