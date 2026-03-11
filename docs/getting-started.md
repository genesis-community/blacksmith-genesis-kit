# Getting Started with Blacksmith

This guide will help you get started with deploying and using Blacksmith as a service broker for Cloud Foundry.

## Prerequisites

Before you begin, you'll need:

1. A working BOSH director
2. A Cloud Foundry deployment (for registering services)
3. Genesis v2.8.5 or higher
4. BOSH CLI v2
5. Cloud Foundry CLI
6. Access to an IaaS environment (vSphere, AWS, Azure, Google Cloud, or OpenStack)

## Installation

### Step 1: Initialize the Deployment Repository

```bash
# Create a new deployment repository
genesis init --kit blacksmith

# Change to the new deployment directory
cd blacksmith-deployments
```

### Step 2: Create a New Environment

```bash
# Create a new environment (interactive)
genesis new my-blacksmith-env

# Or create from a template
genesis new my-blacksmith-env --template vsphere
```

During environment creation, you'll be prompted for:

- Environment name
- IaaS provider (vsphere, aws, azure, google, openstack, stackit, or external-bosh)
- IaaS-specific credentials and configuration
- Service forges to enable (postgresql, rabbitmq, redis, valkey, mariadb, kubernetes)
- Static IP for the Blacksmith broker
- Additional features (TLS, SHIELD backups, etc.)

### Step 3: Edit the Environment Configuration

Open the generated YAML file for your environment and customize as needed:

```bash
# Edit the environment file
$EDITOR my-blacksmith-env.yml
```

Be sure to:
- Configure cloud_config for the Blacksmith internal BOSH director
- Add stemcells for service deployments
- Configure service plans for your enabled forges

### Step 4: Deploy Blacksmith

```bash
# Deploy Blacksmith
genesis deploy my-blacksmith-env
```

### Step 5: Register with Cloud Foundry

Once Blacksmith is deployed, register it with your Cloud Foundry instance:

```bash
# Register with the default CF environment
genesis do my-blacksmith-env register

# Register with a specific CF environment
genesis do my-blacksmith-env register my-cf-env
```

## Verifying the Deployment

### Check the Broker Status

```bash
# View the broker status in the web UI (macOS only)
genesis do my-blacksmith-env visit

# Check service offerings in CF
cf marketplace
```

### Test a Service

Create a test service instance:

```bash
# Create a small PostgreSQL service instance
cf create-service postgresql small-standalone my-test-db

# Check the service status
cf service my-test-db
```

## Basic Operations

### Managing Service Instances

```bash
# Create a service instance
cf create-service SERVICE_TYPE PLAN_NAME SERVICE_NAME

# Delete a service instance
cf delete-service SERVICE_NAME

# List all service instances
cf services
```

### Accessing the BOSH Director

```bash
# Set up the BOSH alias and authenticate
genesis do my-blacksmith-env bosh

# List service deployments
bosh deployments
```

### Using the boss CLI

If you have the boss CLI installed, you can interact directly with the Blacksmith broker:

```bash
# Run boss commands
genesis do my-blacksmith-env boss catalog
```

## Next Steps

- Explore [IaaS-specific configurations](iaas/README.md)
- Learn about configuring [service forges](forges/README.md)
- Review [security best practices](security.md)