# Valkey Forge

The Valkey forge provides on-demand Valkey key-value store instances. Valkey is a Redis-compatible, open-source key-value store that supports multiple versions and deployment modes.

## Features

- **Version Selection**: Parameterized version control (default: LTS v8, configurable to 7 or 9)
- **Standalone Mode**: Single-node deployment for development and small workloads
- **Cluster Mode**: Multi-node clusters with automatic sharding and replication
- **TLS Support**: Optional TLS encryption for data in transit
- **Dual-Mode TLS**: Support for both TLS and non-TLS connections simultaneously
- **Persistence**: Configurable RDB and AOF persistence options
- **Resource Control**: Configurable memory limits and eviction policies

## Basic Configuration

To enable the Valkey forge, add it to your kit features:

```yaml
kit:
  features:
    - valkey
```

## Service Plans

The forge provides four default plans. All default to the LTS version (currently v8):

- `standalone`: Single-node Valkey instance
- `cluster`: Multi-node Valkey cluster with 3 masters + 3 replicas
- `standalone-classic`: as `standalone`, with shared-password credentials
- `cluster-classic`: as `cluster`, with shared-password credentials

The `-classic` plans deploy exactly the same Valkey as their counterparts. They differ only in the credentials a bound application receives (see [Credential Modes](#credential-modes)). They require valkey-forge v1.1.1 or later.

The `version` parameter selects which Valkey major version to deploy (7, 8, or 9). Operators can define additional plans at different versions (e.g., a `standalone-edge` plan using version 9).

## Configuration Parameters

### Service Configuration

```yaml
params:
  valkey_service_id: "valkey"
  valkey_service_name: "valkey"
  valkey_service_description: "A dedicated Valkey instance, deployed on-demand"
  valkey_service_tags:
    - blacksmith
    - dedicated
    - valkey
    - redis
  valkey_service_limit: 0  # 0 = unlimited
```

**Important**

Cloudfoundry applications utilize service tags to enable the service binding. Before creating the service instance make sure that you set the correct tags for your application to take advantage of the service binding.

### Custom Plans

You can customize plans or create new ones:

```yaml
params:
  valkey_plans:
    standalone:
      name: standalone
      description: A dedicated Valkey server, with no redundancy or replication
      limit: 7
      type: standalone
      version: 8
      vm_type: default

    cluster:
      name: cluster
      description: A Valkey cluster with 3 master nodes and 3 replica nodes
      limit: 5
      type: cluster
      version: 8
      vm_type: default

    standalone-edge:
      name: standalone-edge
      description: Valkey 9 server with latest features
      limit: 3
      type: standalone
      version: 9
      vm_type: default

    custom-large:
      name: custom-large
      description: Large Valkey instance with extra memory
      limit: 3
      type: standalone
      version: 8
      vm_type: large
```

**Note:** The `type` field must be `standalone` or `cluster` — it selects the plan template. The `version` field selects which Valkey binary to use (7, 8, or 9). Multiple plans can share the same type with different versions.

## TLS Configuration

### Enable TLS

To enable TLS for all Valkey connections:

```yaml
kit:
  features:
    - valkey
    - valkey-tls

# TLS certificates will be stored in Vault at:
# (( vault meta.vault "/tls/ca:certificate" ))
# (( vault meta.vault "/tls/ca:key" ))
```

### Dual-Mode TLS

To support both TLS and non-TLS connections:

```yaml
kit:
  features:
    - valkey
    - valkey-dual-mode
```

## Plan Types

### Standalone Plans

Standalone plans deploy a single Valkey instance. Best for:
- Development and testing
- Low-traffic applications
- Caching layers where data loss is acceptable

### Cluster Plans

Cluster plans deploy a multi-node Valkey cluster with automatic sharding and replication. Best for:
- Production workloads requiring high availability
- Large datasets that need horizontal scaling
- Applications requiring fault tolerance

## Credential Modes

Each plan type comes in two flavours, which deploy the same Valkey and differ only in the credentials a bound application receives.

**Per-binding ACL** (`standalone`, `cluster`)

Each binding gets its own Valkey ACL user, so the application must authenticate with the two-argument `AUTH <username> <password>`. Unbinding removes that user. An application that sends only a password authenticates as the `default` user and is rejected with `WRONGPASS`.

**Classic** (`standalone-classic`, `cluster-classic`)

Every binding receives the same shared password, so the application authenticates with the single-argument `AUTH <password>`. Nothing is created or removed on the instance when an application binds or unbinds.

Both flavours can be offered in the same catalog. When migrating an existing service, point the plan your applications already use at the `-classic` type and offer the ACL type as an opt-in, so no application has to change its client code before it is ready.

```yaml
params:
  valkey_plans:
    shared:                     # existing password-only applications
      type: standalone-classic
      version: 8
    secure:                     # applications that can send a username
      type: standalone
      version: 8
```

## Version Selection

Set the `version` parameter on any plan to select the Valkey major version:

| Version | Description | Default |
|---------|-------------|---------|
| 7 | Stable, Redis 7.x compatible | |
| 8 | LTS, recommended for production | yes |
| 9 | Latest with advanced features | |

## Connection Information

After provisioning a Valkey instance, connection credentials are provided via service binding:

```json
VCAP_SERVICES: {
  "valkey": [
    {
      "binding_guid": "99a7fd19-376d-42eb-bd7b-f0c4a77a63de",
      "binding_name": null,
      "credentials": {
        "host": "65d620db-590a-4060-a41f-d40fe6dfcad8.standalone.ocfp-aws-lab-ocf-us-east-1-cf-net-ocf.valkey-standalone-d618ff1d-6b50-403e-9d11-2f9d6c0ae72b.bosh",
        "password": "E1bOo1bwUK18Bo0kM7xj9eiVVgPe3mgsvPmyQxCt70nRIIw9Xz1UcP7KtFJ1HGf4",
        "port": 6379,
        "tls_port": 16379,
        "tls_versions": [
          "tlsv1.2",
          "tlsv1.3"
        ]
      },
      "instance_guid": "d618ff1d-6b50-403e-9d11-2f9d6c0ae72b",
      "instance_name": "valkeys8",
      "label": "valkey",
      "name": "valkeys8",
      "plan": "standalone",
      "provider": null,
      "syslog_drain_url": null,
      "tags": [
        "blacksmith",
        "dedicated",
        "valkey",
        "redis"
      ],
      "volume_mounts": []
    }
  ]
}
```

For clusters, additional fields are provided:

```json
VCAP_SERVICES: {
  "valkey": [
    {
      "binding_guid": "cc451ee5-6adc-4f67-af61-7d37daad6f8a",
      "binding_name": null,
      "credentials": {
        "host": "48f45726-df6f-4274-b8b7-3f846e30bd15.node.ocfp-aws-lab-ocf-us-east-1-cf-net-ocf.valkey-cluster-470fb7bb-1726-4471-a143-470dc1c01e6d.bosh",
        "hosts": [
          "10.0.2.41",
          "10.0.2.103",
          "10.0.2.159",
          "10.0.2.42",
          "10.0.2.104",
          "10.0.2.160"
        ],
        "password": "Ir58iCwfr2NGEhYN2x3DBgAutKGUoQ7x2bprYx9ZjZ9H2gX6iqssogQ5BfNDv9bg",
        "port": 6379,
        "tls_port": 16379,
        "tls_versions": [
          "tlsv1.2",
          "tlsv1.3"
        ]
      },
      "instance_guid": "470fb7bb-1726-4471-a143-470dc1c01e6d",
      "instance_name": "valkeyc8",
      "label": "valkey",
      "name": "valkeyc8",
      "plan": "cluster",
      "provider": null,
      "syslog_drain_url": null,
      "tags": [
        "blacksmith",
        "dedicated",
        "valkey",
        "redis"
      ],
      "volume_mounts": []
    }
  ]
}
```

## Example Environment

Complete example for a production Valkey deployment:

```yaml
---
kit:
  name: blacksmith
  version: latest
  features:
    - ocfp
    - valkey
    - valkey-dual-mode

genesis:
  env: ocfp-aws-lab-ocf-us-east-1

meta:
  azs:
    - (( concat genesis.env "-z1" ))
    - (( concat genesis.env "-z2" ))
    - (( concat genesis.env "-z3" ))
  valkey_plan:
    network: (( concat genesis.env "-cf-net-ocf" ))
    azs: (( grab meta.azs ))
    persist: true

params:
  blacksmith:
    

  # Valkey service configuration
  valkey_service_name: "valkey"
  valkey_service_description: "High-performance Valkey key-value store"
  valkey_service_limit: 50
  
  valkey_plans:
    standalone:
      name: standalone
      description: A dedicated Valkey server, with no redundancy or replication
      limit: 7
      type: standalone
      version: 8
      vm_type: redis-small
      .: (( inject meta.valkey_plan ))
    standalone-edge:
      name: standalone-edge
      description: A dedicated Valkey 9 server with edge features
      limit: 7
      type: standalone
      version: 9
      vm_type: redis-small
      .: (( inject meta.valkey_plan ))
    cluster:
      name: cluster
      description: A Valkey cluster with 3 master nodes and 3 replica nodes
      limit: 5
      type: cluster
      version: 8
      vm_type: redis-small
      masters: 3
      replicas: 1
      .: (( inject meta.valkey_plan ))
```

## Best Practices

1. **Use Clusters for Production**: Always use cluster plans for production workloads requiring high availability
2. **Enable TLS**: Use `valkey-tls` feature for production deployments
3. **Set Appropriate Limits**: Configure per-plan and global limits to prevent resource exhaustion
4. **Choose the Right VM Type**: Size VMs appropriately based on expected memory and CPU needs
5. **Monitor Resource Usage**: Track memory usage and connection counts
6. **Regular Backups**: Enable SHIELD backups for persistent data
7. **Version Testing**: Test application compatibility when upgrading Valkey versions

## Troubleshooting

### Connection Issues

If applications cannot connect to Valkey:

1. Verify security groups allow traffic on port 6379 (or 16379 for TLS)
2. Check service binding credentials are correctly injected
3. Verify TLS configuration matches between client and server

### Memory Issues

If Valkey instances run out of memory:

1. Check current memory usage via Valkey CLI
2. Review eviction policies
3. Consider upgrading to larger VM types
4. Enable RDB/AOF persistence to disk if appropriate

### Cluster Split-Brain

In rare cases, cluster nodes may become partitioned:

1. Check network connectivity between nodes
2. Review BOSH instance health
3. Use Valkey cluster repair commands if needed
4. Consider reprovisioning the service instance

## Related Documentation

- [Blacksmith Architecture](../architecture.md)
- [Forge Configuration](README.md)
- [Troubleshooting Guide](../troubleshooting.md)
