# Kubernetes Forge

The Kubernetes forge allows Blacksmith to deploy dedicated Kubernetes clusters as on-demand services through Cloud Foundry.

## Overview

The Kubernetes forge deploys containerized application platforms that can be used by development teams to run containerized workloads. Each service instance is a separate Kubernetes cluster with its own control plane and worker nodes.

## Features

- **Isolated Clusters**: Each service instance is a fully isolated Kubernetes cluster
- **Flexible Sizing**: Configure the number and size of control plane and worker nodes
- **BOSH Management**: Leverage BOSH for deployment, scaling, and healing
- **CF Integration**: Credentials delivered via standard service binding

## Enabling the Forge

To enable the Kubernetes forge, add the `kubernetes` feature to your Blacksmith deployment manifest:

```yaml
kit:
  features:
    - <iaas-feature>  # vsphere, aws, etc.
    - kubernetes
```

## Service Configuration

The Kubernetes forge supports the following service configuration parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `kubernetes_service_name` | Name shown in the marketplace | `kubernetes` |
| `kubernetes_service_id` | Unique identifier for the service | `kubernetes` |
| `kubernetes_service_description` | Service description | `A dedicated Kubernetes cluster, deployed on-demand.` |
| `kubernetes_service_tags` | List of tags for the service | `[blacksmith, kubernetes, dedicated]` |
| `kubernetes_service_limit` | Maximum number of instances | `0` (unlimited) |

## Plan Configuration

Kubernetes plans require separate configuration for control plane nodes (masters) and worker nodes:

```yaml
kubernetes_plans:
  small-cluster:
    type: cluster
    master:
      vm_type: medium        # Control plane VM type
      network: services      # Network for control plane
      disk: 16_384           # Disk size for control plane (MB)
      instances: 1           # Number of control plane nodes
    workers:
      vm_type: large         # Worker node VM type
      network: services      # Network for workers
      disk: 32_768           # Disk size for workers (MB)
      instances: 3           # Number of worker nodes
    limit: 5                 # Maximum number of instances
```

### Plan Parameters

| Parameter | Description |
|-----------|-------------|
| `type` | Must be `cluster` for Kubernetes |
| `master.vm_type` | VM type for control plane nodes (from cloud-config) |
| `master.network` | Network for control plane nodes (from cloud-config) |
| `master.disk` | Disk size for control plane nodes (MB) |
| `master.instances` | Number of control plane nodes (1 for non-HA, 3 or more for HA) |
| `workers.vm_type` | VM type for worker nodes (from cloud-config) |
| `workers.network` | Network for worker nodes (from cloud-config) |
| `workers.disk` | Disk size for worker nodes (MB) |
| `workers.instances` | Number of worker nodes |
| `limit` | Maximum number of instances for this plan |

## Example Configuration

Here's a complete example of a Kubernetes forge configuration with multiple plans:

```yaml
params:
  kubernetes_service_name: kubernetes
  kubernetes_service_description: "On-demand Kubernetes clusters"
  kubernetes_service_tags: [blacksmith, kubernetes, containers, dedicated]
  
  kubernetes_plans:
    small:
      type: cluster
      master:
        vm_type: small
        network: services
        disk: 16_384
        instances: 1
      workers:
        vm_type: small
        network: services
        disk: 32_768
        instances: 2
      limit: 10
      
    medium:
      type: cluster
      master:
        vm_type: medium
        network: services
        disk: 32_768
        instances: 3
      workers:
        vm_type: medium
        network: services
        disk: 65_536
        instances: 3
      limit: 5
      
    large:
      type: cluster
      master:
        vm_type: large
        network: services
        disk: 65_536
        instances: 3
      workers:
        vm_type: large
        network: services
        disk: 131_072
        instances: 5
      limit: 2
```

## Using a Kubernetes Service Instance

### Creating an Instance

```bash
# Create a small Kubernetes cluster
cf create-service kubernetes small my-k8s
```

### Binding to an Application

```bash
# Bind the Kubernetes cluster to an application
cf bind-service my-app my-k8s
```

The binding provides credentials including:

- Kubernetes API server URL
- Authentication credentials (certificates or tokens)
- Connection information (ports, etc.)

### Accessing the Cluster

After binding, you can access the Kubernetes cluster using the `kubectl` CLI:

1. Retrieve the credentials from the application's environment variables:
   ```bash
   cf env my-app
   ```

2. Extract and save the kubeconfig information to a file

3. Use kubectl with the config file:
   ```bash
   kubectl --kubeconfig=/path/to/config get nodes
   ```

## Operational Considerations

### Resource Requirements

Kubernetes clusters require significant resources. Consider the following minimums:

- Control plane nodes: At least 2 CPUs, 4GB RAM
- Worker nodes: At least 2 CPUs, 4GB RAM, 20GB disk

### High Availability

For production use, consider these HA recommendations:

- At least 3 control plane nodes for control plane HA
- At least 3 worker nodes across multiple availability zones
- Adequate CPU, memory, and disk resources for workload redundancy

### Network Requirements

Kubernetes has specific network requirements:

- All cluster nodes must be able to communicate with each other
- Worker nodes must be able to reach the control plane
- Applications need access to the Kubernetes API server

### Upgrades and Patches

Kubernetes clusters deployed by Blacksmith will be updated when:

1. The Blacksmith deployment is updated with a new Kubernetes release
2. The service instance is upgraded via `cf update-service`

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**:
   - Check BOSH task logs for deployment errors
   - Verify resource quota availability in your IaaS
   - Ensure network connectivity between nodes

2. **Application Can't Connect to Cluster**:
   - Verify credentials in the application environment
   - Check network connectivity between the application and cluster
   - Confirm the Kubernetes API server is running

3. **Cluster Performance Issues**:
   - Check if resource limits are adequate for workloads
   - Review node utilization and consider scaling
   - Check for network connectivity issues between nodes