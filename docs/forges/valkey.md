# Valkey Forge

The Valkey forge provides on-demand Valkey key-value store instances. Valkey is a Redis-compatible, open-source key-value store that supports multiple versions and deployment modes.

## Features

- **Multiple Versions**: Support for Valkey 7, 8, and 9
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

The forge provides default plans for both standalone and cluster deployments across all supported versions:

### Standalone Plans

- `standalone-7`: Valkey 7.x single-node instance
- `standalone-8`: Valkey 8.x single-node instance  
- `standalone-9`: Valkey 9.x single-node instance

### Cluster Plans

- `cluster-7`: Valkey 7.x cluster (3 masters + 3 replicas)
- `cluster-8`: Valkey 8.x cluster (3 masters + 3 replicas)
- `cluster-9`: Valkey 9.x cluster (3 masters + 3 replicas)

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
    standalone-9:
      name: standalone-9
      description: A dedicated Valkey 9 server, with no redundancy or replication
      limit: 7
      type: standalone-9
      vm_type: default
    
    cluster-9:
      name: cluster-9
      description: A Valkey 9 cluster with 3 master nodes and 3 replica nodes
      limit: 5
      type: cluster-9
      vm_type: default
      
    custom-large:
      name: custom-large
      description: Large Valkey 9 instance with extra memory
      limit: 3
      type: standalone-9
      vm_type: large
```

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

## Version Selection

Choose the Valkey version based on your requirements:

- **Valkey 7**: Stable, Redis 7.x compatible
- **Valkey 8**: Latest stable with new features, Redis 7.x+ compatible
- **Valkey 9**: Latest version with advanced features, Redis 7.x+ compatible

## Connection Information

After provisioning a Valkey instance, connection credentials are provided via service binding:

```json
VCAP_SERVICES: {
  "valkey": [
    {
      "binding_guid": "99a7fd19-376d-42eb-bd7b-f0c4a77a63de",
      "binding_name": null,
      "credentials": {
        "host": "65d620db-590a-4060-a41f-d40fe6dfcad8.standalone.ocfp-aws-lab-ocf-us-east-1-cf-net-ocf.valkey-standalone-8-d618ff1d-6b50-403e-9d11-2f9d6c0ae72b.bosh",
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
      "plan": "standalone-8",
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
        "host": "48f45726-df6f-4274-b8b7-3f846e30bd15.node.ocfp-aws-lab-ocf-us-east-1-cf-net-ocf.valkey-cluster-8-470fb7bb-1726-4471-a143-470dc1c01e6d.bosh",
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
      "plan": "cluster-8",
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
    standalone-7:
      name: standalone-7
      description: A dedicated Valkey 7 server, with no redundancy or replication
      limit: 7
      type: standalone-7
      vm_type: redis-small
      .: (( inject meta.valkey_plan ))
    standalone-8:
      name: standalone-8
      description: A dedicated Valkey 8 server, with no redundancy or replication
      limit: 7
      type: standalone-8
      vm_type: redis-small
      .: (( inject meta.valkey_plan ))
    standalone-9:
      name: standalone-9
      description: A dedicated Valkey 9 server, with no redundancy or replication
      limit: 7
      type: standalone-9
      vm_type: redis-small
      .: (( inject meta.valkey_plan ))
    cluster-7:
      name: cluster-7
      description: A Valkey 7 cluster with 3 master nodes and 3 replica nodes
      limit: 5
      type: cluster-7
      vm_type: redis-small
      masters: 3
      replicas: 1
      .: (( inject meta.valkey_plan ))
    cluster-8:
      name: cluster-8
      description: A Valkey 8 cluster with 3 master nodes and 3 replica nodes
      limit: 5
      type: cluster-8
      vm_type: redis-small
      masters: 3
      replicas: 1
      .: (( inject meta.valkey_plan ))
    cluster-9:
      name: cluster-9
      description: A Valkey 9 cluster with 3 master nodes and 3 replica nodes
      limit: 5
      type: cluster-9
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
