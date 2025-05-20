# Blacksmith Addons

Blacksmith Genesis Kit provides several addons to help you interact with and manage your Blacksmith deployment. These addons provide convenient shortcuts for common tasks and operations.

## Available Addons

| Addon | Description |
|-------|-------------|
| `visit` | Opens the Blacksmith Web UI in your browser |
| `register` | Registers Blacksmith with a Cloud Foundry instance |
| `bosh` | Sets up the BOSH CLI to talk to Blacksmith's internal BOSH director |
| `boss` | Interacts with Blacksmith via the boss CLI |
| `curl` | Makes direct API calls to the Blacksmith broker |

## Using Addons

To use any of the Blacksmith addons, use the `genesis do` command:

```bash
genesis do <environment-name> <addon-name> [arguments]
```

For example:

```bash
genesis do my-blacksmith visit
```

## Addon Details

### `visit`

Opens the Blacksmith Web Management Console in your browser. This addon only works on macOS.

```bash
genesis do my-blacksmith visit
```

The web interface provides:
- Service catalog overview
- Current service instances and their status
- Detailed service instance information
- Access to logs and troubleshooting information

The interface is protected by HTTP basic authentication, but the addon handles this automatically using the credentials stored in your Genesis vault.

### `register`

Registers this Blacksmith Broker with a Cloud Foundry instance.

```bash
# Register with the default CF environment (based on current environment)
genesis do my-blacksmith register

# Register with a specific CF environment
genesis do my-blacksmith register cf-production
```

This addon:
1. Retrieves the Blacksmith broker URL and credentials
2. Connects to the specified Cloud Foundry deployment
3. Registers the broker using `cf create-service-broker` or updates it using `cf update-service-broker`
4. Enables access to the services in the marketplace

If the broker is already registered, it will be updated with the latest configuration.

### `bosh`

Sets up a local alias for the Blacksmith internal BOSH director and logs you in.

```bash
genesis do my-blacksmith bosh
```

After running this command, you'll be able to use the BOSH CLI directly to interact with the Blacksmith BOSH director:

```bash
# List deployments managed by Blacksmith
bosh deployments

# Check a specific service deployment
bosh -d <deployment-name> instances

# SSH to a service VM
bosh -d <deployment-name> ssh <instance-name>
```

This is particularly useful for troubleshooting service instances or checking their status.

### `boss`

Runs the `boss` CLI to interact directly with the Blacksmith broker through the Open Service Broker API.

```bash
# View the service catalog
genesis do my-blacksmith boss catalog

# List service instances
genesis do my-blacksmith boss instances

# Get info about a specific instance
genesis do my-blacksmith boss instance <instance-id>
```

This requires that you have the `boss` CLI installed. You can download it from https://github.com/jhunt/boss/releases.

Boss provides a more direct interface to the broker compared to the Cloud Foundry CLI, which can be useful for troubleshooting or advanced operations.

### `curl`

Makes direct HTTP requests to the Blacksmith broker's API.

```bash
# Get broker status
genesis do my-blacksmith curl /b/status

# Get the service catalog
genesis do my-blacksmith curl /v2/catalog
```

This addon is useful for troubleshooting or accessing API endpoints that aren't exposed through other tools. It automatically handles authentication.

## Tips for Using Addons

### Automation

You can use these addons in scripts for automation:

```bash
#!/bin/bash
# Deploy and register Blacksmith
genesis deploy my-blacksmith
genesis do my-blacksmith register my-cf

# Check if the deployment succeeded
if genesis do my-blacksmith curl /b/status | grep -q '"status":"ok"'; then
  echo "Blacksmith deployed successfully!"
else
  echo "Blacksmith deployment has issues!"
fi
```

### Troubleshooting

When troubleshooting service issues:

1. Use `visit` to check the Blacksmith Web UI for any obvious errors
2. Use `bosh` to check the BOSH deployment for the service instance
3. Use `boss` to verify the service instance status from the broker's perspective
4. Use `curl` for direct API access if needed

### Service Management Lifecycle

For managing the entire lifecycle of your Blacksmith deployment:

1. Deploy Blacksmith with `genesis deploy my-blacksmith`
2. Register it with Cloud Foundry using `genesis do my-blacksmith register`
3. Access the Web UI with `genesis do my-blacksmith visit` to monitor operations
4. Use `genesis do my-blacksmith bosh` to access the BOSH director for maintenance
5. Update Blacksmith with `genesis deploy my-blacksmith`

## Additional Information

For more detailed information on using these addons, refer to:

- [Blacksmith BOSH Release Documentation](https://github.com/cloudfoundry-community/blacksmith-boshrelease)
- [boss CLI Documentation](https://github.com/jhunt/boss)
- [Open Service Broker API Specification](https://github.com/openservicebrokerapi/servicebroker/blob/master/spec.md)