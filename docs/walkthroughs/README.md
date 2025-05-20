# Blacksmith Deployment Walkthroughs

This directory contains detailed walkthroughs for deploying Blacksmith on various infrastructure providers and configuring different service types.

## Available Walkthroughs

- [AWS Deployment](aws-deployment.md) - Deploy Blacksmith on Amazon Web Services
- [Azure Deployment](azure-deployment.md) - Deploy Blacksmith on Microsoft Azure
- [Google Cloud Deployment](google-deployment.md) - Deploy Blacksmith on Google Cloud Platform

## Common Deployment Steps

Regardless of the IaaS provider, all Blacksmith deployments follow these general steps:

1. **Initialize a Genesis deployment repository**
   ```bash
   genesis init --kit blacksmith
   ```

2. **Create an environment configuration**
   ```bash
   cd blacksmith-deployments
   genesis new my-env --template <iaas>
   ```

3. **Edit the environment YAML file**
   - Configure IaaS-specific parameters
   - Add service forges
   - Configure service plans
   - Set up internal BOSH director cloud config

4. **Deploy Blacksmith**
   ```bash
   genesis deploy my-env
   ```

5. **Register with Cloud Foundry**
   ```bash
   genesis do my-env register cf-env
   ```

6. **Create service instances**
   ```bash
   cf create-service <service-type> <plan> <service-name>
   ```

## Choosing a Walkthrough

Select the walkthrough that matches your target infrastructure:

- For **AWS**: Follow [AWS Deployment](aws-deployment.md)
- For **Azure**: Follow [Azure Deployment](azure-deployment.md)
- For **Google Cloud**: Follow [Google Cloud Deployment](google-deployment.md)
- For **vSphere**: Refer to examples in the [main manual](../MANUAL.md)

## Additional Resources

After completing the basic deployment, you may want to explore:

- [RabbitMQ Walkthrough](../../rabbitmq-walkthrough.md) - Setting up RabbitMQ services
- [Kubernetes Configuration](../forges/kubernetes.md) - Setting up Kubernetes services
- [Troubleshooting Guide](../troubleshooting.md) - Solving common deployment issues