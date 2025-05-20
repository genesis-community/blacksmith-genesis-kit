# Blacksmith Architecture

Blacksmith is an on-demand service broker that leverages BOSH to deploy and manage service instances. This document outlines the high-level architecture and key components of the system.

## System Components

![Blacksmith Architecture](../assets/blacksmith.png)

Blacksmith consists of several key components:

1. **Blacksmith Service Broker** - The main component that implements the Open Service Broker API (OSBAPI) and manages service instance requests.

2. **Internal BOSH Director** - A dedicated BOSH director used by Blacksmith to deploy and manage service VMs.

3. **Forges** - Specialized components that know how to deploy specific types of services (PostgreSQL, RabbitMQ, Redis, etc.)

4. **Service Instances** - BOSH deployments that run the actual service software.

## Request Flow

When a user requests a service instance through Cloud Foundry, the following happens:

1. CF marketplace sends the request to the Blacksmith Service Broker (via OSBAPI)
2. Blacksmith validates the request against available plans and quotas
3. Blacksmith uses the appropriate Forge to generate a BOSH manifest for the service
4. The Internal BOSH Director deploys the service using the manifest
5. Blacksmith generates credentials and returns them to Cloud Foundry
6. Cloud Foundry makes the credentials available to the application

## Blacksmith Service Broker

The Blacksmith Service Broker is responsible for:

- Implementing the Open Service Broker API
- Managing the service catalog and plans
- Validating and processing service requests
- Delegating deployment tasks to the BOSH Director
- Managing credentials and service bindings
- Maintaining state information for all service instances

## Internal BOSH Director

Blacksmith deploys its own internal BOSH Director (or connects to an external one) which:

- Provides VM orchestration for service instances
- Manages VM lifecycle (create, update, delete)
- Handles stemcell and release management
- Ensures VM health and performs resurrection
- Manages persistent disks for stateful services

## Forges

Forges are specialized components that know how to deploy specific types of services:

- Each forge handles a specific service type (PostgreSQL, RabbitMQ, etc.)
- Forges define the BOSH releases, stemcells, and job configurations needed
- They translate generic service parameters into specific deployment options
- Forges handle service-specific operations (e.g., cluster formation, leader election)

## Service Instances

Each service instance is a separate BOSH deployment that:

- Contains one or more VMs running the service software
- Has its own dedicated networking and storage
- Is isolated from other service instances
- Can be scaled independently
- Has service-specific monitoring and management

## Security Model

Blacksmith employs a multi-layered security approach:

1. **Network Isolation** - Service instances run on dedicated subnets
2. **Credential Isolation** - Each service instance has unique credentials
3. **TLS Encryption** - Communication can be secured with TLS
4. **BOSH Security** - Leverages BOSH's security model for VM management
5. **Role-based Access** - Different users have different levels of access

## Integration Points

Blacksmith integrates with various external systems:

1. **Cloud Foundry** - Via the Open Service Broker API
2. **IaaS Providers** - Through the BOSH director (vSphere, AWS, Azure, GCP, etc.)
3. **SHIELD** - For backup and restore capabilities
4. **Monitoring Systems** - Via metrics exposure and logging

## Deployment Models

Blacksmith supports multiple deployment models:

1. **Standalone Service** - Single VM deployments for simple services
2. **Clustered Service** - Multi-VM deployments for HA services
3. **Custom Configurations** - Tailored deployments for specific needs

## Data Flow

![Blacksmith Data Flow](../assets/blacksmith.png)

1. **Creation Flow**:
   - User requests service → CF marketplace → Blacksmith → BOSH → deployed service
   - Credentials generated → stored in Blacksmith → returned to CF → provided to application

2. **Binding Flow**:
   - Application binds to service → CF requests binding → Blacksmith creates credentials → CF injects credentials into application

3. **Deletion Flow**:
   - User deletes service → CF marketplace → Blacksmith → BOSH deletes deployment
   - Blacksmith removes state information and credentials