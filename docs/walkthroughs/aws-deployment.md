# AWS Deployment Walkthrough

This walkthrough provides a step-by-step guide for deploying Blacksmith on Amazon Web Services (AWS) and configuring it to offer PostgreSQL database services.

## Prerequisites

Before starting this walkthrough, you should have:

1. A working BOSH director targeting AWS
2. A Cloud Foundry deployment (for service registration)
3. Genesis 2.8.5+ installed
4. BOSH CLI v2
5. Cloud Foundry CLI
6. AWS account with appropriate permissions
7. AWS access key and secret key

## Step 1: Initialize the Deployment Repository

First, create a new deployment repository using the Blacksmith Genesis Kit:

```bash
# Create a new repository
genesis init --kit blacksmith

# Navigate to the repository
cd blacksmith-deployments
```

## Step 2: Configure AWS Cloud Config

Ensure your BOSH director has a cloud config that includes:

1. Networks for Blacksmith and services
2. VM types appropriate for Blacksmith and services
3. Disk types for service data

Here's an example cloud config snippet for AWS:

```yaml
networks:
  - name: blacksmith
    type: manual
    subnets:
      - range: 10.0.4.0/24
        gateway: 10.0.4.1
        az: us-east-1a
        dns: [169.254.169.253]
        reserved: [10.0.4.1-10.0.4.10]
        static: [10.0.4.11-10.0.4.50]
        cloud_properties:
          subnet: subnet-abc123def

  - name: services
    type: manual
    subnets:
      - range: 10.0.5.0/24
        gateway: 10.0.5.1
        az: us-east-1a
        dns: [169.254.169.253]
        reserved: [10.0.5.1-10.0.5.10]
        cloud_properties:
          subnet: subnet-xyz456uvw

vm_types:
  - name: blacksmith
    cloud_properties:
      instance_type: t3.medium
      ephemeral_disk:
        size: 10240
        type: gp2
      
  - name: small-postgresql
    cloud_properties:
      instance_type: t3.medium
      ephemeral_disk:
        size: 10240
        type: gp2

  - name: large-postgresql
    cloud_properties:
      instance_type: m5.large
      ephemeral_disk:
        size: 20480
        type: gp2

disk_types:
  - name: blacksmith
    disk_size: 20480
    cloud_properties:
      type: gp2
      
  - name: postgresql-small
    disk_size: 10240
    cloud_properties:
      type: gp2
      
  - name: postgresql-large
    disk_size: 51200
    cloud_properties:
      type: gp2
```

## Step 3: Create the Blacksmith Environment

Create a new environment YAML file:

```bash
# Create an AWS environment
genesis new aws-blacksmith --template aws
```

This will create a file named `aws-blacksmith.yml`. Open it in your editor and customize it:

```yaml
kit:
  name: blacksmith
  version: latest
  features:
    - aws
    - postgresql
    - broker-tls

params:
  # Basic broker settings
  env: aws-blacksmith
  ip: 10.0.4.11
  
  # AWS settings
  aws_region: us-east-1
  aws_access_key: AKIAIOSFODNN7EXAMPLE
  aws_secret_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  aws_default_security_groups:
    - blacksmith
    - bosh-controlled
  
  # PostgreSQL service settings
  postgresql_service_name: postgresql
  postgresql_service_description: "AWS-hosted PostgreSQL databases"
  postgresql_plans:
    small:
      type: standalone
      vm_type: small-postgresql
      network: services
      disk: postgresql-small
      limit: 10
    
    large:
      type: standalone
      vm_type: large-postgresql
      network: services
      disk: postgresql-large
      limit: 5
  
  # Cloud configuration for the internal BOSH director
  cloud_config:
    azs:
      - name: z1
        cloud_properties:
          availability_zone: us-east-1a
    
    networks:
      - name: services
        type: manual
        subnets:
          - range: 10.0.5.0/24
            gateway: 10.0.5.1
            az: z1
            dns: [169.254.169.253]
            cloud_properties:
              subnet: subnet-xyz456uvw
    
    vm_types:
      - name: small
        cloud_properties:
          instance_type: t3.small
          ephemeral_disk:
            size: 10240
            type: gp2
      
      - name: medium
        cloud_properties:
          instance_type: t3.medium
          ephemeral_disk:
            size: 20480
            type: gp2
    
    disk_types:
      - name: small
        disk_size: 10240
        cloud_properties:
          type: gp2
      
      - name: medium
        disk_size: 20480
        cloud_properties:
          type: gp2
    
    compilation:
      workers: 3
      reuse_compilation_vms: true
      az: z1
      vm_type: medium
      network: services
  
  # Stemcells for service deployments
  stemcells:
    - name: bosh-aws-xen-hvm-ubuntu-bionic-go_agent
      version: latest
      url: https://bosh.io/d/stemcells/bosh-aws-xen-hvm-ubuntu-bionic-go_agent
      sha1: auto
```

## Step 4: Deploy Blacksmith

Deploy the environment:

```bash
# Deploy Blacksmith
genesis deploy aws-blacksmith
```

This will:
1. Create a BOSH deployment for Blacksmith
2. Deploy the Blacksmith broker VM
3. Set up the internal BOSH director
4. Upload necessary stemcells and releases
5. Configure the specified service forges

## Step 5: Register with Cloud Foundry

Register the Blacksmith broker with your Cloud Foundry deployment:

```bash
# Register with CF
genesis do aws-blacksmith register cf-aws
```

Replace `cf-aws` with the name of your Cloud Foundry environment.

## Step 6: Verify the Installation

Check that the broker is properly registered and the services are available:

```bash
# List service brokers
cf service-brokers

# Check marketplace for PostgreSQL
cf marketplace | grep postgresql
```

You should see the PostgreSQL service with the plans you configured.

## Step 7: Create a Service Instance

Create a test service instance:

```bash
# Create a small PostgreSQL instance
cf create-service postgresql small my-postgres
```

Monitor the service creation:

```bash
# Check service status
cf service my-postgres
```

You can also use the Blacksmith Web UI to monitor the deployment:

```bash
# Open the Web UI (macOS only)
genesis do aws-blacksmith visit
```

## Step 8: Bind to an Application

Deploy a sample application and bind it to the service:

```bash
# Clone a sample app
git clone https://github.com/cloudfoundry-samples/spring-music
cd spring-music

# Build the app (requires Java)
./gradlew clean assemble

# Deploy to CF
cf push spring-music --no-start

# Bind to PostgreSQL
cf bind-service spring-music my-postgres

# Start the app
cf start spring-music
```

## AWS-Specific Considerations

### Security Groups

Ensure your AWS security groups allow:

1. Communication between Blacksmith and the BOSH director
2. Communication between Blacksmith and the internal BOSH director
3. Communication between service instances and client applications
4. Communication between nodes in clustered services

### IAM Permissions

The AWS access key and secret key provided should have permissions to:

1. Create and manage EC2 instances
2. Create and manage EBS volumes
3. Create and manage security groups (if dynamic security groups are used)
4. Access S3 buckets (if BOSH uses S3 for blobstore)

### Network Considerations

1. Ensure your VPC subnets have enough IP addresses for all planned service instances
2. Configure route tables to allow communication between subnets
3. Consider using private subnets with NAT gateways for service instances

### Resource Limits

Be aware of AWS resource limits, such as:

1. EC2 instance quotas per region
2. EBS volume limits
3. VPC limits

## Troubleshooting

### Common AWS-Specific Issues

1. **"InvalidKeyPair" errors**:
   - Verify the SSH key specified exists in AWS
   - Check region-specific key availability

2. **"InstanceLimitExceeded" errors**:
   - You've hit your EC2 instance quota
   - Request a limit increase from AWS

3. **"InsufficientInstanceCapacity" errors**:
   - AWS doesn't have capacity for the requested instance type
   - Try a different instance type or availability zone

4. **Network connectivity issues**:
   - Check security group rules
   - Verify subnet routing tables and network ACLs
   - Ensure DNS resolution is working properly

### Debugging AWS Deployments

For AWS-specific debugging:

```bash
# Check AWS CPI logs
genesis do aws-blacksmith bosh logs --job aws_cpi

# Verify AWS credentials
aws configure list

# Test AWS API access
aws ec2 describe-instances

# Check for resource constraints
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A
```

## Next Steps

1. **Configure backup and restore**:
   - Add the `shield-backups` feature
   - Set up S3 bucket policies for backups

2. **Add more service offerings**:
   - Configure Redis, RabbitMQ, or other services
   - Define appropriate AWS VM and disk types

3. **Set up monitoring**:
   - Configure CloudWatch for AWS resource monitoring
   - Set up monitoring for Blacksmith and services

4. **Scale for production**:
   - Adjust VM sizes based on workload
   - Consider multi-AZ deployments for HA

5. **Set up CI/CD**:
   - Automate deployments and updates
   - Implement blue/green deployment strategies