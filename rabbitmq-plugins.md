# RabbitMQ Plugin Configuration Guide

## Table of Contents
1. [Introduction](#1-introduction)
2. [Understanding RabbitMQ Plugins](#2-understanding-rabbitmq-plugins])
3. [New Plugin Configuration Feature](#3-new-plugin-configuration-feature)
4. [Configuring Plugins for New Deployments](#4-configuring-plugins-for-new-deployments)
5. [Updating Existing Deployments](#5-Updating-Existing-Deployments)
6. [Available Plugins](#6-Available-Plugins)
7. [Best Practices](#7-best-practices)
8. [Troubleshooting](#8-troubleshooting)
9. [FAQ](9-faq)

## 1. Introduction

This guide provides comprehensive information on how to use the new plugin configuration feature for RabbitMQ deployments. With this feature, operators can easily enable and manage RabbitMQ plugins for both new and existing deployments.

## 2. Understanding RabbitMQ Plugins

RabbitMQ plugins extend the functionality of RabbitMQ, providing additional features such as management interfaces, monitoring capabilities, and protocol support. Plugins can be enabled or disabled to customize your RabbitMQ instance to your specific needs.

## 3. New Plugin Configuration Feature

Our new plugin configuration feature allows for dynamic selection and management of RabbitMQ plugins through Blacksmith BOSH deployment manifests. This feature provides greater flexibility and easier management of RabbitMQ instances.

Key benefits:
- Configure plugins during service broker Blacksmith deployment 
- Update plugin configurations for existing RabbitMQ instance deployments
- Consistent plugin management across all instances

## 4. Configuring Plugins for New Deployments

To enable new RabbitMQ Instance deployments with configured plugins, you can easily configure plugins by specifying them in your Blacksmith genesis deployment manifest. After you deploy Blacksmith deployment, all the new RabbitMQ instances created afther Blacksmith deployed is configured with the plugins you enabled by default. Here's how:

1. Open your Blacksmith genesis deployment manifest file for the new deployment.

2. Locate the `params` section in the manifest. If it doesn't exist, create it.

3. Add a `rabbitmq_plugins` list under the `params` section, specifying the plugins you want to enable. For example:

   ```yaml
   params:
     rabbitmq_plugins:
     - rabbitmq_consistent_hash_exchange
     - rabbitmq_federation
     - rabbitmq_federation_management
   ```

4. Save the changes to your deployment manifest.

5. Deploy your Blacksmith environment using this manifest:

   ```
   genesis deploy <your-new-environment>
   ```

6. During the deployment process, confirm that:
   - The plugins property is being applied. Look for log lines indicating the addition of the specified plugins.

7. After the the Blacksmith deployment is complete, verify that the plugins are enabled:
   - Create a new RabbitMQ service instance
   - SSH into the newely created RabbitMQ instance
   - Run `source /var/vcap/jobs/rabbitmq/env` then `rabbitmq-plugins list` to see the enabled plugins or
   - `cat /var/vcap/sys/log/rabbitmq/rabbitmq.log` which will show the enablement of the plugins

Note: The `rabbitmq_management` plugin is typically enabled by default. If you need it, you don't have to explicitly include it in your list unless you're overriding a default set of plugins.

## 5. Updating Existing RabbitMQ Instance Deployments

To update plugin configurations for existing RabbitMQ instance deployments:

1. Ensure that the latest BOSH release, which includes the new plugin configuration feature, has been uploaded to your BOSH director. If not, upload it using:

   ```
   bosh upload-release path/to/latest-rabbitmq-forge-release.tgz
   ```

2. Update your RabbitMQ deployment manifest:
   - Download and save the manifest `bosh -d rabbitmq-single-node-fcab211b-dffd-478d-8537-5ba2b7c4d5bb manifest > single-plugins-manifest.yml`
   - Add or modify the `plugins` property under the `properties` section of the `rabbitmq` job specification

   For example:

   ```yaml

   jobs:
   - name: rabbitmq
     # ...
     properties:
       plugins:
         - rabbitmq_management
         - rabbitmq_prometheus
   ```

3. Redeploy your RabbitMQ instance using the updated manifest:

   ```
   bosh -d rabbitmq-single-node-fcab211b-dffd-478d-8537-5ba2b7c4d5bb deploy single-plugins-manifest.yml
   ```

4. During the deployment process, confirm that:
   - The latest release version is being used. You should see something like:
     ```
     Using release 'rabbitmq-forge/1.2.6'
     ```
   - The new plugins property is being applied. Look for log lines similar to:
     ```
           properties:
     +       plugins:
     +       - rabbitmq_consistent_hash_exchange
     +       - rabbitmq_federation
     +       - rabbitmq_federation_management
     ```


Note: Updating plugins may cause a brief interruption in service as RabbitMQ restarts to apply the new configuration.

## 6. Available Plugins

Here's a list of commonly used RabbitMQ plugins:

- rabbitmq_management: Provides an HTTP-based API for management and monitoring (enabled by default)
- rabbitmq_prometheus: Exposes RabbitMQ metrics in Prometheus format
- rabbitmq_shovel: Provides a way to reliably move messages from one broker to another
- rabbitmq_federation: Provides a way to link brokers across a WAN
- rabbitmq_auth_backend_ldap: Provides support for LDAP authentication

For a complete list of available plugins, refer to the official RabbitMQ documentation.

## 7. Best Practices

- Only enable plugins that you need to minimize resource usage
- Test plugin configurations in a non-production environment before deploying to production
- Regularly review and update your plugin configurations to ensure they meet your current needs
- Monitor performance after enabling new plugins to ensure they don't negatively impact your RabbitMQ instance

## 8. Troubleshooting

If you encounter issues with plugin configuration:

1. Check the RabbitMQ logs for any error messages:
   ```
   bosh -d rabbitmq-three-node-9b28f536-7ff6-4616-accd-7512f93bb74c ssh node/59213905-82c4-46d4-988e-c572ddb6b9b3
   cat /var/vcap/sys/log/rabbitmq/rabbitmq.log
   ```

2. Verify that the plugins are correctly listed in your RabbitMQ deployment manifest

3. Ensure that the plugins you're trying to enable are compatible with your RabbitMQ version

4. If a plugin fails to enable, try enabling it manually on the RabbitMQ server to see if there are any dependency issues:
   ```
   rabbitmq-plugins enable plugin_name
   ```

## 9. FAQ

Q: Can I disable all plugins?
A: A number of plugins are enabled by default (rabbitmq_management, rabbitmq_management_agent, rabbitmq_web_dispatch). You don't have to enable more for basic funstionality.

Q: Will enabling plugins affect performance?
A: Some plugins may have a minor impact on performance. Always test in a non-production environment first.

Q: Can I enable plugins that aren't in the official RabbitMQ distribution?
A: This feature is designed to work with official RabbitMQ plugins. Custom plugins may require additional configuration.

For further assistance, please contact our support team or refer to the official RabbitMQ documentation.
