# Improvements

- Update BOSH director to 268.1.0

- For **vSphere** Blacksmith implementations, the Blacksmith
  Director will now begin placing VMs, Disks, and Stemcells in a
  new directory that ends in `-blacksmith`, so that they are not
  co-mingled with VMs, disks, or stemcell templates from a BOSH
  director with the same environment name.

  Existing VMs, disks and stemcells will stay where they are, and
  BOSH will be totally okay with that.

# Core Components

| Release | Version | Release Date |
| ------- | ------- | ------------ |
| bosh | [268.1.0](https://github.com/cloudfoundry/bosh/releases/tag/v268.1.0) | - |
| bpm (new) | [0.12.3](https://github.com/cloudfoundry-incubator/bpm-release/releases/tag/v0.12.3) | - |
| bosh-azure-cpi | [35.4.0](https://github.com/cloudfoundry/bosh-azure-cpi-release/releases/tag/v35.4.0) | - |
| bosh-google-cpi | [27.0.1](https://github.com/cloudfoundry/bosh-google-cpi-release/releases/tag/v27.0.1) | - |
| bosh-aws-cpi | [72](https://github.com/cloudfoundry/bosh-aws-cpi-release/releases/tag/v72) | - |
| bosh-vsphere-cpi | [50](https://github.com/cloudfoundry/bosh-vsphere-cpi-release/releases/tag/v50) | - |
| bosh-openstack-cpi | [39](https://github.com/cloudfoundry/bosh-openstack-cpi-release/releases/tag/v39) | - |
| blacksmith | [1.0.2](https://github.com/blacksmith-community/blacksmith-boshrelease/releases/tag/v1.0.2) | - |
| mariadb-forge | [0.0.1](https://github.com/blacksmith-community/mariadb-forge-boshrelease/releases/tag/v0.0.1) | - |
| postgresql-forge | [0.1.1](https://github.com/blacksmith-community/postgresql-forge-boshrelease/releases/tag/v0.1.1) | - |
| rabbitmq-forge | [0.1.2](https://github.com/blacksmith-community/rabbitmq-forge-boshrelease/releases/tag/v0.1.2) | - |
| redis-forge | [0.1.0](https://github.com/blacksmith-community/redis-forge-boshrelease/releases/tag/v0.1.0) | - |
