blacksmith Genesis Kit
=================

The Blacksmith Genesis Kit give you the ability to deploy
on-demand services in Cloud Foundry, using the Open Service Broker
API.  These services will be backed by real VMs, running under the
watchful eye of a dedicated BOSH director.

For more information on Blacksmith itself, check out the
[Blacksmith Project Page on Github][blacksmith] and the
[Blacksmith BOSH Release Docs][blacksmith-bosh].

Quick Start
-----------

To use it, you don't even need to clone this repository! Just run
the following (using Genesis v2):

```
# create a blacksmith-deployments repo using the latest version of the blacksmith kit
genesis init --kit blacksmith

# create a blacksmith-deployments repo using v1.0.0 of the blacksmith kit
genesis init --kit blacksmith/1.0.0

# create a my-blacksmith-configs repo using the latest version of the blacksmith kit
genesis init --kit blacksmith -d my-blacksmith-configs
```

Once created, refer to the deployment repo's README for information on creating
new environments.

Learn More
----------

For more in-depth documentation, check out the [manual][2].


[1]: https://github.com/genesis-community/blacksmith-genesis-kit/issues
[2]: MANUAL.md

[blacksmith]: https://github.com/cloudfoundry-community/blacksmith
[blacksmith-bosh]: https://github.com/cloudfoundry-community/blacksmith-boshrelease
