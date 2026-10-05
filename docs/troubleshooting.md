# Blacksmith Troubleshooting Guide

This guide covers common issues you might encounter when deploying and using Blacksmith, along with solutions and debugging approaches.

## Table of Contents

- [Deployment Issues](#deployment-issues)
- [Service Broker Registration Issues](#service-broker-registration-issues)
- [Service Instance Creation Issues](#service-instance-creation-issues)
- [Service Binding Issues](#service-binding-issues)
- [IaaS-Specific Issues](#iaas-specific-issues)
- [Forge-Specific Issues](#forge-specific-issues)
- [Common Error Messages](#common-error-messages)
- [Log Locations](#log-locations)
- [Advanced Debugging Techniques](#advanced-debugging-techniques)
- [When Blacksmith isn't answering](#when-blacksmith-isnt-answering)

## Deployment Issues

### Blacksmith Fails to Deploy

**Symptoms:**
- The `genesis deploy` command fails
- BOSH reports deployment errors

**Possible Causes and Solutions:**

1. **Missing Required Parameters**
   - Check that all required parameters for your selected IaaS are provided
   - Ensure `ip` is set to a valid IP in your network range
   - Confirm cloud config and network settings match your environment

2. **Network Issues**
   - Verify the network specified in the deployment exists in your cloud config
   - Ensure the `ip` parameter is within the static IP range of the network
   - Check that the BOSH director can reach the network

3. **Resource Constraints**
   - Ensure your IaaS has enough resources to deploy Blacksmith
   - Check that the VM type exists in your cloud config
   - Verify there are no conflicting BOSH deployments

4. **Certificate Issues**
   - If using `broker-tls`, check that certificates are properly configured
   - Run `genesis check my-blacksmith-env` to validate certificates
   - Try regenerating certificates with `genesis add-secrets my-blacksmith-env`

**Debugging Steps:**

```bash
# Check the broker's status and its recent BOSH tasks
genesis do my-blacksmith-env -- curl /b/status
genesis do my-blacksmith-env -- curl /b/tasks

# View the broker's logs
genesis do my-blacksmith-env -- curl /b/blacksmith/logs

# Check for certificate issues
genesis check my-blacksmith-env
```

## Service Broker Registration Issues

### Cannot Register with Cloud Foundry

**Symptoms:**
- The `genesis do my-blacksmith-env register` command fails
- CF reports errors about the service broker

**Possible Causes and Solutions:**

1. **Blacksmith Broker Not Accessible from CF**
   - Check network connectivity between CF and Blacksmith
   - Ensure the `ip` or `fqdn` is reachable from CF
   - Try using `curl` to verify the broker is running: `genesis do my-blacksmith-env -- curl /v2/catalog`

2. **Authentication Failure**
   - Verify broker credentials are correct
   - Check that the credentials are properly passed to CF

3. **TLS Certificate Issues**
   - If using `broker-tls`, ensure CF trusts the certificate
   - If the broker logs `CF endpoint marked unhealthy ... tls: failed to verify`, it does not trust the CF haproxy certificate. With the `cf-integration` feature, set `cf_cacert` to the CA that signs it, or enable the `cf-haproxy-ca` feature when CF uses the cf kit's `self-signed` feature. `cf_skip_ssl_validation` turns verification off for development.

4. **Service Already Registered**
   - If the broker is already registered, try updating it instead
   - Check for existing broker registrations with `cf service-brokers`

**Debugging Steps:**

```bash
# Check if broker is running
genesis do my-blacksmith-env -- curl /b/status

# Check broker credential access
genesis do my-blacksmith-env -- curl /v2/catalog

# List existing service brokers
cf service-brokers

# Try to manually register the broker
cf create-service-broker <broker-name> <username> <password> <url>
```

## Service Instance Creation Issues

### Service Instance Creation Fails

**Symptoms:**
- `cf create-service` command fails or gets stuck in "in progress"
- The service instance doesn't appear in Blacksmith's deployed services

**Possible Causes and Solutions:**

1. **BOSH Deployment Failures**
   - Check the BOSH tasks for errors: `genesis do my-blacksmith-env -- curl /b/tasks`
   - Look for BOSH deployment error messages
   - Check for IaaS resource constraints or quotas

2. **Stemcell or Release Issues**
   - Verify that required stemcells and releases are uploaded to the internal BOSH director
   - Check that stemcells match your IaaS (e.g., AWS stemcells for AWS deployments)

3. **Network or Resource Configuration Issues**
   - Ensure the service plan specifies a valid network from the cloud config
   - Check that VM types and disk types exist in the cloud config
   - Verify that the IaaS has capacity for the requested resources

4. **Plan Quota Issues**
   - Check if you've hit the limit for service instances in the plan
   - Verify the global service limit hasn't been reached

**Debugging Steps:**

```bash
# Check broker status and catalog
genesis do my-blacksmith-env -- curl /b/status
genesis do my-blacksmith-env -- curl /v2/catalog

# Check BOSH tasks for errors
genesis do my-blacksmith-env -- curl /b/tasks

# Check the stemcells on the internal BOSH director
genesis do my-blacksmith-env -- curl /b/bosh/stemcells

# View detailed service instance status
cf service <service-instance-name>
genesis do my-blacksmith-env open  # Check Web UI
```

## Service Binding Issues

### Cannot Bind Service to Application

**Symptoms:**
- `cf bind-service` command fails
- Application cannot access the service
- Credentials are missing or incorrect

**Possible Causes and Solutions:**

1. **Service Instance Not Fully Provisioned**
   - Check that the service instance creation completed successfully
   - Verify the service is running with `cf service <service-instance-name>`

2. **Credential Generation Failure**
   - Check Blacksmith logs for credential generation errors
   - Verify the service is healthy and can accept new credentials

3. **Network Connectivity Issues**
   - Ensure the application can reach the service network
   - Check if network policy rules are blocking access

4. **Permission Issues**
   - Verify the user has permission to bind services
   - Check service sharing settings if the service is in a different space

**Debugging Steps:**

```bash
# Check service instance status
cf service <service-instance-name>

# Try creating a service key to test credential generation
cf create-service-key <service-instance-name> test-key
cf service-key <service-instance-name> test-key

# Check Blacksmith logs
genesis do my-blacksmith-env -- curl /b/blacksmith/logs

# Test network connectivity (from a test app)
cf ssh <app-name> -c "nc -zv <service-host> <service-port>"
```

## IaaS-Specific Issues

### vSphere Issues

- **Error**: "Unable to find specified datacenter"
  - Verify the `vsphere_datacenter` parameter matches your vCenter exactly
  - Check vCenter permissions for the BOSH/Blacksmith user

- **Error**: "No valid datastore available with required free space"
  - Ensure the datastores specified in `vsphere_ephemeral_datastores` and `vsphere_persistent_datastores` exist
  - Check free space in the datastores
  - Verify the datastores are accessible to the specified clusters

### AWS Issues

- **Error**: "AuthFailure: AWS was not able to validate the provided credentials"
  - Verify `aws_access_key` and `aws_secret_key` are correct
  - Check that the IAM user has necessary permissions

- **Error**: "VPCResourceNotSpecified: The specified instance type can only be used in a VPC"
  - Ensure the networks in cloud_config are properly configured for VPC
  - Check subnet configurations and CIDR blocks

### Azure Issues

- **Error**: "Azure API request failed"
  - Verify all Azure credentials and parameters
  - Check Azure subscription status and quotas
  - Ensure the specified resource group exists

### Google Cloud Issues

- **Error**: "Failed to authenticate"
  - Verify the `google_json_key` is valid and complete
  - Check the service account has required permissions

- **Error**: "Quota exceeded"
  - Check GCP resource quotas for your project
  - Request quota increases if needed

## Forge-Specific Issues

### PostgreSQL Issues

- **Error**: "Role already exists"
  - This can happen if a previous service instance wasn't properly cleaned up
  - Try manually cleaning up the old role on the PostgreSQL server

- **Error**: "Could not connect to server"
  - Check network connectivity between the PostgreSQL nodes
  - Verify VM health and resource utilization

### RabbitMQ Issues

- **Error**: "Failed to set up cluster"
  - Check network connectivity between RabbitMQ nodes
  - Verify Erlang cookie is consistent across nodes
  - Check node names and hostname resolution

- **Error**: "Failed authentication"
  - Verify credentials in the binding or service key
  - Check if RabbitMQ user permissions are properly set

- For more RabbitMQ troubleshooting, see the [RabbitMQ Walkthrough](../rabbitmq-walkthrough.md)

### Redis Issues (deprecated forge)

> The Redis forge is deprecated — use Valkey for new service
> instances. These notes apply to existing Redis instances; see the
> [Redis to Valkey migration walkthroughs](walkthroughs/README.md)
> for moving off Redis.

- **Error**: "WRONGPASS Invalid Password"
  - Verify credentials in the binding
  - Check if Redis AUTH is properly configured

- **Error**: "Error loading RDB dump file"
  - Check Redis persistence configuration
  - Verify disk space and permissions

### Kubernetes Issues

- **Error**: "Node not ready"
  - Check network connectivity between Kubernetes nodes
  - Verify resource availability and utilization
  - Check container runtime service status

- **Error**: "Failed to pull image"
  - Verify network connectivity to container registries
  - Check image name and tag are correct
  - Ensure registry credentials are configured if needed

## Common Error Messages

### "Cannot establish connection to broker"

- Check if Blacksmith VM is running
- Verify network connectivity to the Blacksmith broker
- Check if the broker process is running on the VM
- Ensure TLS settings match between client and server if using TLS

### "Service broker error: 10001 - Quota Exceeded"

- You've reached the maximum number of instances for a plan or service
- Check plan limits in your configuration
- Increase limits or delete unused service instances

### "Service broker error: 10003 - Not Implemented"

- The operation you're trying is not supported by Blacksmith
- Check that your forge supports the requested feature
- Verify you're using a supported service command

### "500 Internal Server Error"

- Check Blacksmith logs for errors
- Verify the broker has enough resources
- Check for issues with the internal BOSH director

## Log Locations

To diagnose issues, check logs in these locations:

**Blacksmith Broker Logs**:
```bash
# Get the broker's logs
genesis do my-blacksmith-env -- curl /b/blacksmith/logs

# Get the broker's recent events
genesis do my-blacksmith-env -- curl /b/blacksmith/events
```

**Internal BOSH Director Logs**:

Blacksmith has no route for the director's own job logs. When we need them, we follow the steps under [When Blacksmith isn't answering](#when-blacksmith-isnt-answering).

**Service Instance Logs**:

The `instances` section of the broker's status lists every service instance along with its `deployment_name`. We can then list the VMs of a deployment, or read its events, through the broker.

```bash
genesis do my-blacksmith-env -- curl /b/status
genesis do my-blacksmith-env -- curl /b/deployments/<service-deployment>/vms
genesis do my-blacksmith-env -- curl /b/deployments/<service-deployment>/events
```

Blacksmith has no route for a deployment's job logs. To download those, we follow the steps under [When Blacksmith isn't answering](#when-blacksmith-isnt-answering).

## Advanced Debugging Techniques

### Working with the director directly

The Blacksmith VM is deployed by the parent BOSH director, and not by Blacksmith's internal director, so the kit has no addon that opens a shell on it. We reach the VM through the parent director that deployed it, using our own `bosh` CLI and the connection details we already hold for that director. The kit does not run this step for us.

Once we have a shell on the VM, the commands below run on the VM itself.

```bash
# Check Blacksmith process
ps -ef | grep blacksmith

# Check Blacksmith configuration
cat /var/vcap/jobs/blacksmith/config/blacksmith.conf

# Check broker logs directly
tail -f /var/vcap/sys/log/blacksmith/blacksmith.log
```

### Inspecting Service Deployments

```bash
# Find the deployment name of a service instance
genesis do my-blacksmith-env -- curl /b/status

# Examine the VMs and the instances of a specific service deployment
genesis do my-blacksmith-env -- curl /b/deployments/<service-deployment-name>/vms
genesis do my-blacksmith-env -- curl /b/deployments/<service-deployment-name>/instances

# Read the deployment's manifest
genesis do my-blacksmith-env -- curl /b/deployments/<service-deployment-name>/manifest
```

To get a shell on a service VM, we open the Blacksmith web UI with `genesis do my-blacksmith-env open`, select the service instance, and start an SSH session from there.

### Using the boss CLI

If you have the boss CLI installed, you can interact directly with the broker:

```bash
# Check service instances
genesis do my-blacksmith-env boss instances

# Get details about a specific instance
genesis do my-blacksmith-env boss instance <instance-id>

# Check catalog
genesis do my-blacksmith-env boss catalog
```

### Recreating Services as a Last Resort

If all else fails, you might need to recreate the service:

1. Unbind all applications from the service
2. Delete the service instance
3. Manually clean up any orphaned BOSH deployments
4. Recreate the service instance
5. Rebind applications

```bash
# Steps for recreation
cf unbind-service <app-name> <service-name>
cf delete-service <service-name>
# Check the broker's view of its service instances and tasks
genesis do my-blacksmith-env -- curl /b/status
genesis do my-blacksmith-env -- curl /b/tasks
# If a deployment was left behind, delete it through the broker
genesis do my-blacksmith-env -- curl /b/deployments/<orphaned-deployment> -X DELETE
# Then recreate
cf create-service <service> <plan> <service-name>
cf bind-service <app-name> <service-name>
```

## When Blacksmith isn't answering

The `/b/` routes all go through the broker, so they stop working when the broker is down. A few jobs also have no broker route at all. These are the director's own job logs, a consistency check with `cck`, an SSH session to the director's VM, and the upload of a release. When the broker is down, deleting an orphaned deployment also has to go this way. For those, we talk to the internal BOSH director directly, using our own `bosh` CLI.

The `bosh` addon prints the director's connection details as shell export lines and runs no command. The output holds a secret, so we load it into our shell with `eval` rather than copying it around.

```bash
eval "$(genesis do my-blacksmith-env bosh)"
```

After that, `BOSH_ENVIRONMENT`, `BOSH_CA_CERT`, `BOSH_CLIENT`, and `BOSH_CLIENT_SECRET` are set in the current shell. The commands below are our own tooling and not something the kit runs for us.

```bash
# Director job logs
bosh -d my-blacksmith-env logs

# Check the director's consistency with the IaaS
bosh -d <service-deployment-name> cck

# Delete a deployment that was left behind, while the broker is down
bosh -d <orphaned-deployment> delete-deployment

# Releases uploaded to the director
bosh releases
```

To SSH to the director's own VM, we use our own `bosh` CLI against the director's deployment in the same way. When we are done, we close the shell or run `unset BOSH_CLIENT_SECRET` so the secret does not linger.

## Getting Help

If these troubleshooting steps don't resolve your issue:

1. Check the [GitHub issues](https://github.com/cloudfoundry-community/blacksmith/issues) for similar problems
2. Open a new issue with:
   - Detailed description of the problem
   - Logs and error messages
   - Blacksmith and forge versions
   - IaaS provider and configuration details
   - Steps to reproduce