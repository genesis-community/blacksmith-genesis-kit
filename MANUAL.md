# Blacksmith Genesis Kit Manual

The **Blacksmith Genesis Kit** deploys a Blacksmith On-Demand
Services Broker for Cloud Foundry. Blacksmith uses BOSH to deploy
new data services instances on behalf of end users.

## Table of Contents

1. [Base Parameters](#base-parameters)
2. [Sizing and Deployment Parameters](#sizing-and-deployment-parameters)
3. [Blacksmith Broker Parameters](#blacksmith-broker-parameters)
4. [HTTP(S) Proxy Parameters](#https-proxy-parameters)
5. [Features](#features)
   - [IaaS Providers](#iaas-providers)
   - [Service Forges](#service-forges)
   - [Additional Features](#additional-features)
6. [Cloud Configuration](#cloud-configuration)
7. [Available Addons](#available-addons)
8. [Examples](#examples)
9. [History](#history)

## Base Parameters

- `ip` - The static IP address to deploy the Blacksmith broker
  to. This must exist within the static range of the `network`.

- `fqdn` - (Optional) The FQDN DNS Name of the Load Balancer 
  fronting the Blacksmith broker.

- `shareable` - When registering the service broker, advertise the
  services as shareable or not.

## Sizing and Deployment Parameters

- `network` - The name of the `network` (per cloud-config) where
  the blacksmith broker will be deployed. Defaults to `blacksmith`.

- `stemcell_os` - The operating system you want to deploy the
  Blacksmith service broker itself on. This defaults to
  `ubuntu-bionic`.

- `stemcell_version` - The version of the stemcell to deploy.
  Defaults to `1.latest`

- `vm_type` - The name of the `vm_type` (per cloud-config) that
  will be used to deploy the blacksmith broker VM. Defaults to
  `blacksmith`.

- `disk_size` - How big of a data disk to provide the Blacksmith
  broker, for persistent storage. Defaults to `20480` (20G).

## Blacksmith Broker Parameters

- `blacksmith_debug` - Whether or not to enable Blacksmith
  debug logging. Defaults to `false`, but you can set it to
  `true` if you really like log output.

- `blacksmith_port` - The TCP port that Blacksmith will bind to
  This defaults to `3000`.

- `blacksmith_tls_port` - The TCP port that Blacksmith will bind to for tls traffic
  This defaults to `443`.

- `blacksmith_tls_certificate` - The certificate blacksmith should present for
  https traffic on the webui and api.

- `blacksmith_tls_key` - The corresponding key for the above certificate.

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
  keys. Most of the time, the Forge manifests will set these
  themselves, but sometimes you need to do your own thing.

- `stemcells` - A list of stemcells that Blacksmith should
  upload to its internal BOSH director, for use by service
  deployments. You will almost always have to specify these,
  since Forge manifests will rarely be in a position to anticipate
  your IaaS choices.

### Rabbitmq Parameters

- `emitter_skip_ssl_validation` - When `rabbitmq-autoscale` feature
  is selected, assuming that your are using self signed certificates,
  you would like to set it to `true`.

- `cf_skip_ssl_validation` - When `rabbitmq-autoscale` feature
  is selected, assuming that your are using self signed certificates,
  you would like to set it to `true`.

## HTTP(S) Proxy Parameters

- `http_proxy` - (Optional) URL of an HTTP proxy to use for any
  outbound HTTP (non-TLS) communication.

- `https_proxy` - (Optional) URL of an HTTP proxy to use for any
  outbound HTTPS (TLS) communication.

- `no_proxy` - A list of IPs, FQDNs, partial domains, etc. to
  skip the proxy and connect to directly. This has no effect if
  the `http_proxy` and `https_proxy` are not set.

## Features

### IaaS Providers

Blacksmith supports multiple infrastructure providers. You must select exactly one of the following IaaS features:

#### vSphere

- `vsphere` - Deploy the on-demand services to a VMWare
  vSphere hypervisor cluster. You will need to provide all of the
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
    where Blacksmith will deploy things. The clusters listed in
    `vsphere_clusters` must exist within this data center.

  - `vsphere_clusters` - A YAML list of vSphere cluster names
    where Blacksmith will deploy service VMs.

#### STACKIT (OpenStack)

- `stackit` - Deploy the on-demand services to a STACKIT
  OpenStack-compatible cloud. You will need to provide all of the
  information Blacksmith needs to contact the STACKIT API for VM
  orchestration purposes.

  Activating this feature also activates the following parameters:

  - `stackit_auth_url` - The URL of the STACKIT authentication endpoint

  - `stackit_username` - The username to authenticate with STACKIT

  - `stackit_password` - The password to authenticate with STACKIT

  - `stackit_domain` - The STACKIT domain name

  - `stackit_project` - The STACKIT project name

  - `stackit_region` - The STACKIT region to deploy to

  - `stackit_ssh_key` - The SSH key name to use for VM authentication

  - `stackit_default_security_groups` - A YAML list of security group names
    to apply to all VMs by default

  Note: STACKIT has a 1:1 correspondence of networks to subnets rather than a 
  single overarching network. This should be considered when designing your 
  cloud-config for STACKIT deployments.

#### AWS

- `aws` - Deploy the on-demand services to Amazon Web Services.
  You will need to provide all of the information Blacksmith needs to
  contact the AWS API for VM orchestration purposes.

  Activating this feature also activates the following parameters:

  - `aws_region` - The AWS region where Blacksmith will deploy VMs

  - `aws_access_key` - AWS access key for API authentication

  - `aws_secret_key` - AWS secret key for API authentication

  - `aws_default_security_groups` - A YAML list of security group names
    to apply to all VMs by default

#### Azure

- `azure` - Deploy the on-demand services to Microsoft Azure.
  You will need to provide all of the information Blacksmith needs to
  contact the Azure API for VM orchestration purposes.

  Activating this feature also activates the following parameters:

  - `azure_environment` - The Azure environment (AzureCloud, AzureUSGovernment, etc.)

  - `azure_subscription_id` - Your Azure subscription ID

  - `azure_tenant_id` - Your Azure tenant ID

  - `azure_client_id` - Your Azure client ID for authentication

  - `azure_client_secret` - Your Azure client secret for authentication

  - `azure_resource_group_name` - The resource group where VMs will be deployed

  - `azure_default_security_group` - The default security group to apply to all VMs

#### Google Cloud

- `google` - Deploy the on-demand services to Google Cloud Platform.
  You will need to provide all of the information Blacksmith needs to
  contact the Google Cloud API for VM orchestration purposes.

  Activating this feature also activates the following parameters:

  - `google_project_id` - Your Google Cloud project ID

  - `google_json_key` - The JSON service account key for authentication

  - `google_default_zone` - The default zone for VM deployments

#### OpenStack

- `openstack` - Deploy the on-demand services to an OpenStack cloud.
  You will need to provide all of the information Blacksmith needs to
  contact the OpenStack API for VM orchestration purposes.

  Activating this feature also activates the following parameters:

  - `openstack_auth_url` - The URL of the OpenStack authentication endpoint

  - `openstack_username` - The username to authenticate with OpenStack

  - `openstack_password` - The password to authenticate with OpenStack

  - `openstack_domain` - The OpenStack domain

  - `openstack_project` - The OpenStack project/tenant

  - `openstack_region` - The OpenStack region for deployment

  - `openstack_default_security_groups` - A YAML list of security group names
    to apply to all VMs by default

#### External BOSH

- `external-bosh` (IaaS substitute) - Deploy the on-demand services to an
  existing bosh director. You will need to provide all of the information
  Blacksmith needs to contact bosh director for deployments orchestration
  purposes.

  Activating this feature also activates the following parameters:

  - `external_bosh.address` - The IP address of the external BOSH director to
    deploy to.

  - `external_bosh.cacert` - The CA certificate of the external BOSH director.

  - `external_bosh.username` - The username to authenticate with the external
    bosh director. This user must have permissions to manage its deployments,
    upload releases and stemcells.

  - `external_bosh.password` - The password for the above user to authenticate
    against the external bosh director.

### Service Forges

Blacksmith uses "forges" to deploy different types of services. You can activate one or more of the following forge features:

#### PostgreSQL

- `postgresql` (Blacksmith Forge) - Enables the Blacksmith Service
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

    Defaults to `blacksmith`, `postgresql`, and `dedicated`. If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `postgresql_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits. `0` (the default) imposes no global
    limit.

  Example configuration:
  ```yaml
  postgresql_plans:
    standalone:
      type: standalone
      vm_type: small
      network: services
      disk: 8_192
      limit: 10
      
    small-cluster:
      type: cluster
      vm_type: medium
      network: services
      disk: 8_192
      limit: 3
  ```

#### RabbitMQ

- `rabbitmq` (Blacksmith Forge) - Enables the Blacksmith Service
  Broker to deploy RabbitMQ messaging clusters. A comprehensive 
  walkthrough can be found [here](rabbitmq-walkthrough.md)

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

    Defaults to `blacksmith`, `rabbitmq`, and `dedicated`. If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `rabbitmq_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits. `0` (the default) imposes no global
    limit.

  Example configuration:
  ```yaml
  rabbitmq_plans:
    single-node:
      type: standalone
      vm_type: small
      network: services
      disk: 8_192
      limit: 10
      
    three-node:
      type: cluster
      vm_type: medium
      network: services
      disk: 8_192
      limit: 5
  ```

  Additional RabbitMQ features:

  - `rabbitmq-tls` - Enables TLS communication to RabbitMQ while
    disabling non-TLS communication altogether.

  - `rabbitmq-dual-mode` - When enabled along with `rabbitmq-tls`, it also
    allows non-TLS communication.

  - `rabbitmq-dashboard-registration` - Adds a routable DNS record
    on CF for the service instances. It requires a CF deployment 
    already in place.

  - `rabbitmq-autoscale` - Enables autoscaling based on RabbitMQ's
    queue depth. It requires a CF deployment already in place
    along with the `app-autoscaler-integration` feature enabled.
    Autoscaling itself requires cf-app-autoscaler-genesis-kit.

#### Redis

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

    Defaults to `blacksmith`, `redis`, and `dedicated`. If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `redis_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits. `0` (the default) imposes no global
    limit.

  Example configuration:
  ```yaml
  redis_plans:
    cache-small:
      type: cache
      vm_type: small
      network: services
      disk: 4_096
      limit: 10
      
    persistent-medium:
      type: persistent
      vm_type: medium
      network: services
      disk: 16_384
      limit: 5
  ```

  Additional Redis features:

  - `redis-tls` - Enables TLS encryption for Redis communications.

  - `redis-dual-mode` - When enabled along with `redis-tls`, allows both
    TLS and non-TLS communication.

#### Valkey

- `valkey` (Blacksmith Forge) - Enables the Blacksmith Service
  Broker to deploy Valkey key-value instances. Valkey is a Redis-compatible
  open-source key-value store supporting versions 7, 8, and 9.

  Activating this feature also activates the following parameters:

  - `valkey_plans` - A YAML fragment that contains the set of
     Cloud Foundry Valkey service plans to offer. Supports both
     standalone and cluster deployment types.

     Each type also has a `-classic` variant
     (`standalone-classic`, `cluster-classic`) that deploys the
     same Valkey but hands bound applications a shared password
     instead of a per-binding ACL user, so password-only clients
     keep working. Requires valkey-forge v1.1.1 or later.

  - `valkey_service_name` - The name of the service, to be
    shown in the services marketplace.

    Defaults to `valkey`.

  - `valkey_service_id` - A globally unique (internal)
    identifier for this service.

    Defaults to `valkey`.

  - `valkey_service_description` - A long-form description of
    the service, for use in both console and web-based UIs.

    Defaults to `A dedicated Valkey instance, deployed
    on-demand.`

  - `valkey_service_tags` - The list of tags to apply to all
    new instances of this service.

    Defaults to `blacksmith`, `valkey`, `dedicated` and `redis`. If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `valkey_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits. `0` (the default) imposes no global
    limit.

  Example configuration:
  ```yaml
  valkey_plans:
    standalone:
      name: standalone
      description: A dedicated Valkey server
      type: standalone
      version: 8
      vm_type: default
      limit: 10

    cluster:
      name: cluster
      description: A Valkey cluster with 3 masters and 3 replicas
      type: cluster
      version: 8
      vm_type: default
      limit: 5

    shared:
      name: shared
      description: A dedicated Valkey server, shared-password credentials
      type: standalone-classic
      version: 8
      vm_type: default
      limit: 10
  ```

  Additional Valkey features:

  - `valkey-tls` - Enables TLS encryption for Valkey communications.

  - `valkey-dual-mode` - When enabled along with `valkey-tls`, allows both
    TLS and non-TLS communication.

#### MariaDB

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

    Defaults to `blacksmith`, `mariadb`, and `dedicated`. If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `mariadb_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits. `0` (the default) imposes no global
    limit.

  Example configuration:
  ```yaml
  mariadb_plans:
    standalone:
      type: standalone
      vm_type: small
      network: services
      disk: 8_192
      limit: 10
  ```

#### Kubernetes

- `kubernetes` (Blacksmith Forge) - Enables the Blacksmith Service
  Broker to deploy Kubernetes container orchestration clusters.

  Activating this feature also activates the following parameters:

  - `kubernetes_plans` - A YAML fragment that contains the set of
     Cloud Foundry Kubernetes service plans to offer.

  - `kubernetes_service_name` - The name of the service, to be
    shown in the services marketplace.

    Defaults to `kubernetes`.

  - `kubernetes_service_id` - A globally unique (internal)
    identifier for this service.

    Defaults to `kubernetes`.

  - `kubernetes_service_description` - A long-form description of
    the service, for use in both console and web-based UIs.

    Defaults to `A dedicated Kubernetes cluster, deployed
    on-demand.`

  - `kubernetes_service_tags` - The list of tags to apply to all
    new instances of this service.

    Defaults to `blacksmith`, `kubernetes`, and `dedicated`. If
    you specify this, and you want the defaults too, you have to
    provide them explicitly.

  - `kubernetes_service_limit` - An upper limit on the number of
    service instances _total_ that can be provisioned, regardless
    of per-plan limits. `0` (the default) imposes no global
    limit.

  Example configuration:
  ```yaml
  kubernetes_plans:
    small:
      type: cluster
      master:
        vm_type: medium
        network: services
        disk: 8_192
      workers:
        vm_type: medium
        network: services
        disk: 16_384
        instances: 3
      limit: 5
  ```

### Additional Features

- `shield-backups` - Enables automatic Blacksmith Service backups
  via S.H.I.E.L.D. scheduled backups.

  This feature requires the `shield` CLI to be available in the
  instance where `genesis deploy` is invoked.

- `broker-tls` - Enables TLS for the Blacksmith broker API and web UI.

- `cf-route-registrar` - Registers the Blacksmith broker with Cloud Foundry
  routes, for easier access from applications.

## Cloud Configuration

By default, Blacksmith uses the following VM types/networks/disk
pools from your cloud config. Feel free to override them in your
environment, if you would rather they use entities already
existing in your cloud config:

```
params:
  network:   blacksmith
  vm_type:   blacksmith
```

## Available Addons

- `visit` - Opens the Blacksmith Web Management Console in your
  browser. This only works on macOS.

  This web interface provides an at-a-glance summary of all the
  salient bits of the Blacksmith broker deployment, the service
  catalog, quotas, and deployed service instances.

  This interface is protected by HTTP basic authentication, and
  this addon takes that into account, without bothering you.

- `register` - Register this Blacksmith Broker with a Cloud
  Foundry instance (deployed by Genesis). Optionally takes the
  name of the CF environment to register with.

  If the service broker is already registered, this will run
  update-service-broker instead.

- `bosh` - Sets up a local alias for the Blacksmith (Internal)
  BOSH director, retrieves the X.509 CA Certificate and BOSH admin
  credentials, and authenticates to it.

  After this runs, you will be able to use the BOSH CLI, unaided,
  to interact with the Blacksmith BOSH director, for
  troubleshooting and diagnostics.

- `boss` - Runs `boss`, a command-line utility for interacting
  directly with Blacksmith via the Open Service Broker API,
  without needing a Cloud Foundry instance.

  This requires that you have `boss` already installed. You can
  get `boss` from https://github.com/jhunt/boss/releases

- `curl` - Run arbitrary HTTP requests against the Blacksmith
  Broker and its API. This is very useful for troubleshooting
  weird Blacksmith issues. The `/b/status` and `/b/catalog`
  endpoints are useful.

## Examples

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

  shareable: true

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

Deploying Blacksmith with a STACKIT director:

```
---
kit:
  name:    blacksmith
  version: 5.6.7
  features:
    - stackit
    - postgresql

params:
  env: acme-stackit-prod

  ip: 10.0.134.4

  shareable: true

  # STACKIT
  stackit_auth_url: https://keystone.api.stackit.example.com:5000/v3
  stackit_region:   region1
  stackit_ssh_key:  blacksmith-key
  stackit_default_security_groups:
    - default
    - blacksmith-sg
```

Since Blacksmith has its own internal BOSH director, you need to
supply a cloud configuration, and stemcells. Here's an example for vSphere:

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

And here's a cloud config example for STACKIT, showing the 1:1 correspondence between networks and subnets:

```
  cloud_config:
    azs:
      - name: z1
        cloud_properties: {}

    networks:
      - name: services
        type: manual
        subnets:
          - range: 10.10.0.0/24
            gateway: 10.10.0.1
            az: z1
            cloud_properties:
              net_id: subnet-services-id-123456

      - name: data
        type: manual
        subnets:
          - range: 10.10.1.0/24
            gateway: 10.10.1.1
            az: z1
            cloud_properties:
              net_id: subnet-data-id-123456

    vm_types:
      - name: small
        cloud_properties:
          instance_type: small
          root_disk_size_gb: 10

      - name: medium
        cloud_properties:
          instance_type: medium
          root_disk_size_gb: 20

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

## History

Version 0.2.0 was the first version to support Genesis 2.6 hooks
for addon scripts and `genesis info`.