# Blacksmith Service Forges

Blacksmith uses "forges" to deploy different types of services. Each forge contains the knowledge of how to deploy a specific type of service and provides customizable plans for end users.

## Available Forges

Blacksmith currently supports the following service forges:

- PostgreSQL - PostgreSQL database services (standalone and clustered)
- RabbitMQ - RabbitMQ message broker services (with TLS, clustering, and autoscaling)
- Valkey - Valkey key-value store services (Redis-compatible, versions 7/8/9)
- Redis (deprecated) - Redis key-value store services; use Valkey for new instances
- MariaDB - MariaDB/MySQL database services

## Forge Configuration 

Each forge needs to be enabled via a feature flag and configured with service plans. A service plan defines the resources and capabilities of the service instances that will be deployed.

### Basic Configuration Pattern

All forges follow a similar configuration pattern:

```yaml
kit:
  features:
    - forge-name  # E.g., postgresql, rabbitmq, valkey, etc.

params:
  forge_service_name: "service-name"          # Name in the marketplace
  forge_service_description: "Description"     # Service description
  forge_service_tags: [tag1, tag2, tag3]       # Service tags
  forge_service_limit: 0                       # Global instance limit (0 = unlimited)
  
  forge_plans:                                 # Service plans
    plan-name:                                 # Name of the plan
      type: standalone|cluster|cache|etc       # Type of deployment
      vm_type: small                           # VM size from cloud-config
      network: services                        # Network from cloud-config
      disk: 10240                              # Disk size in MB
      limit: 10                                # Per-plan instance limit
      # Additional plan-specific parameters...
```

## Common Parameters

All forges support these common parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `*_service_name` | Name shown in the marketplace | Varies by forge |
| `*_service_id` | Unique identifier for the service | Varies by forge |
| `*_service_description` | Service description | Varies by forge |
| `*_service_tags` | List of tags for the service | `[blacksmith, <forge-name>, dedicated]` |
| `*_service_limit` | Maximum number of instances across all plans | `0` (unlimited) |

## Plan Parameters

Plans for all forges include these common parameters:

| Parameter | Description |
|-----------|-------------|
| `type` | Type of deployment (standalone, cluster, etc.) |
| `vm_type` | VM type from cloud-config to use |
| `network` | Network from cloud-config to use |
| `disk` | Disk size in MB |
| `limit` | Maximum number of instances for this plan |

## Forge-Specific Features

Some forges have additional feature flags that enable special capabilities:

- **RabbitMQ**:
  - `rabbitmq-tls` - Enable TLS encryption
  - `rabbitmq-dual-mode` - Allow both TLS and non-TLS connections
  - `rabbitmq-dashboard-registration` - Register management UI with CF routes
  - `rabbitmq-autoscale` - Enable autoscaling based on queue depth

- **Valkey**:
  - `valkey-tls` - Enable TLS encryption
  - `valkey-dual-mode` - Allow both TLS and non-TLS connections

- **Redis** (deprecated — use Valkey for new instances):
  - `redis-tls` - Enable TLS encryption
  - `redis-dual-mode` - Allow both TLS and non-TLS connections

## Using Service Instances

After a service is created, you can bind it to applications:

```bash
# Create a service instance
cf create-service postgresql small-standalone my-database

# Bind to an application
cf bind-service my-app my-database

# Display service information
cf service my-database
```

For more detailed information about each forge, refer to the individual forge documentation pages.