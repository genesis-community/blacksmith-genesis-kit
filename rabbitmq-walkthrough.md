# Rabbitmq Forge - Features and Validation Tests

## Introduction
So you've turned to Blacksmith once again to deploy your precious managed service. This time around messaging is the need and rabbitmq is the tool of choice. The following lines will walk you through the changes you need to introduce on blacksmith's deployment manifest to deploy rabbitmq, the features available of the deployed rabbitmq service, and different ways to test them, providing you at the same time, a clear path in troubleshooting your deployment in the future.

## Prerequisites

### External Bosh
Blacksmith used to exist all by itself, firing up its own bosh director to deploy and manage the service instances. This was introducing another resource to be managed and maintained, while adding little if anything to the service broker's usability. Given the detached status between blacksmith's director, and the director hosting most if not all of the resources using its services, it was hindering interconnectivity between the blacksmith's deployed services and the ones available to bosh director hosting our cloudfoundry deployment. That said, a decision has been made to use `- external-bosh` as the default feature in deploying blacksmith. This is expecting `blacksmith_user` and `blacksmith_password` under `secret/exodus/dev/bosh` (where dev is the environment name) with credentials to the bosh director.

### Cloudfoundry
Rabbitmq forge has gone a long way since its first introduction. A lot of changes and features where added with the most prominent one being autoscaling based on rabbitmq's queue depth. Given its dependencies, when `rabbitmq-autoscale` feature and plans are added to blacksmith, it is expecting a cloudfoundry deployment with the `- app-autoscaler-integration` feature enabled.


## Deploying rabbitmq
As in all genesis kits, all you need to do is to provide the corresponding configuration lines on the deployment manifest. Bellow is an example of said manifest

```yaml
kit:
  name:    dev
  version: latest
  features:
    - external-bosh
    - rabbitmq
    - rabbitmq-tls  
    - rabbitmq-dual-mode
    - rabbitmq-dashboard-registration ## Needs cf
    - rabbitmq-autoscale ## Needs cf-app-autoscaler
exodus:
  broker_url: (( concat "https://" params.fqdn ))
meta:
  rabbitmq_plan:
    azs: [z1,z2,z3]
    network: blacksmith
params:
  env: dev
  ip:  10.7.16.8
  blacksmith_debug: true
  fqdn: blacksmith.system.codex2.starkandwayne.com
  emitter_skip_ssl_validation: true
  cf_skip_ssl_validation: true
  route_registrar_tls_enabled: true

instance_groups:
- name: blacksmith
  azs: [z1,z2,z3]
  vm_extensions:
    - (( replace ))
    - blacksmith-alb
  jobs:
    - name: rabbitmq-blacksmith-plans
      release: rabbitmq-forge
      properties:
        plans:
          single-node:
            limit: 10
            description: "Small dedicated RabbitMQ node"
            name: single-node
            type: standalone
            vm_type: blacksmith-rabbitmq-medium
            disk: 30GB
            .: (( inject meta.rabbitmq_plan ))
          three-node:
            limit: 10
            description: "3-node RabbitMQ cluster"
            name: three-node
            type: cluster
            vm_type: blacksmith-rabbitmq-medium
            disk: 30GB
            .: (( inject meta.rabbitmq_plan ))
          large-single-node:
            limit: 10
            description: "Large dedicated RabbitMQ node"
            name: large-single-node
            type: standalone
            vm_type: blacksmith-rabbitmq-large
            disk: 75GB
            .: (( inject meta.rabbitmq_plan ))
          large-three-node:
            limit: 10
            description: "3-node RabbitMQ cluster"
            name: large-three-node
            type: cluster
            vm_type: blacksmith-rabbitmq-large
            disk: 75GB
            .: (( inject meta.rabbitmq_plan ))
releases:
- name:    blacksmith
  version: 1.6.5
  url:     https://github.com/blacksmith-community/blacksmith-boshrelease/releases/download/v1.6.5/blacksmith-1.6.5.tgz
  sha1:    1def8e4e21d3ea95aaf16339d4dec64667538ae9
```

A successful deployment of the above blacksmith manifest (or a variation of, that matches your choices) should be followed by the registration of the broker using the addon `genesis do envname register`. Once blacksmith has been registered, cf will report the available plans provided earlier:

`cf marketplace`

```
Getting all service offerings from marketplace in org system / space dev as admin...

offering   plans                                                          description                                         broker
rabbitmq   large-single-node, large-three-node, single-node, three-node   A dedicated RabbitMQ instance, deployed on-demand   dev-blacksmith

TIP: Use 'cf marketplace -e SERVICE_OFFERING' to view descriptions of individual plans of a given service offering.
```

and as per the tip, a slightly more verbose version:

`cf marketplace -e rabbitmq`

```java
Getting service plan information for service offering rabbitmq in org system / space dev as admin...

broker: dev-blacksmith
   plan                description                     free or paid   costs
   large-single-node   Large dedicated RabbitMQ node
   free           
   large-three-node    3-node RabbitMQ cluster
         free           
   single-node         Small dedicated RabbitMQ node
   free           
   three-node          3-node RabbitMQ cluster
         free           
```

## Creating the service instances

With blacksmith deployed, registered and the services available at your disposal through cf's marketplace, you are ready to start deploying the service instances with their corresponding plans. For completeness, we will deploy all available plans:

`cf create-service rabbitmq single-node rmqsmall`

```
Creating service instance rmqsmall in org system / space dev as admin...

Create in progress. Use 'cf services' or 'cf service rmqsmall' to check operation status.
OK
```

`cf create-service rabbitmq large-single-node rmqlarge`

```
Creating service instance rmqlarge in org system / space dev as admin...

Create in progress. Use 'cf services' or 'cf service rmqlarge' to check operation status.
OK
```

`cf create-service rabbitmq three-node rmqclustersmall`

```
Creating service instance rmqclustersmall in org system / space dev as admin...

Create in progress. Use 'cf services' or 'cf service rmqclustersmall' to check operation status.
OK
```

`cf create-service rabbitmq large-three-node rmqclusterlarge`

```
Creating service instance rmqclusterlarge in org system / space dev as admin...

Create in progress. Use 'cf services' or 'cf service rmqclusterlarge' to check operation status.
OK
```

By the time you get yourself a fresh cup of coffee (5 minutes in our testing environment), the following services should be available through cf

`cf services`

```
Getting service instances in org system / space dev as admin...

name              offering   plan                bound apps   last operation     broker           upgrade available
rmqclusterlarge   rabbitmq   large-three-node                 create succeeded   dev-blacksmith   no
rmqclustersmall   rabbitmq   three-node                       create succeeded   dev-blacksmith   no
rmqlarge          rabbitmq   large-single-node                create succeeded   dev-blacksmith   no
rmqsmall          rabbitmq   single-node                      create succeeded   dev-blacksmith   no
```

## <a name="binding"></a>Binding the service

As much as everyone would like to have (all the) services available to them at all times, its when using them that makes a difference. To use rabbitmq you need to bind it to an application. For the requirements of this document, lets go ahead and clone a forked version of [cf-rabbitmq-example-app](https://github.com/itsouvalas/cf-rabbitmq-example-app):

`git clone https://github.com/itsouvalas/cf-rabbitmq-example-app`

`cd cf-rabbitmq-example-app`

`cf push`

```
Pushing app rabbitmq to org system / space dev as admin...
...
start command:   bundle exec rackup config.ru -p $PORT
     state     since                  cpu    memory          disk          logging      details
#0   running   2022-10-20T12:44:17Z   0.2%   34.3M of 256M   91.4M of 1G   0/s of 0/s   
```

With the application available we are ready to bind it to the deployed service:

`cf bind-service rabbitmq rmqsmall`

```
Binding service instance rmqsmall to app rabbitmq in org system / space dev as admin...
OK

TIP: Use 'cf restage rabbitmq' to ensure your env variable changes take effect
```

As per the tip, lets go ahead and restage the application:

`cf restage rabbitmq`

```
This action will cause app downtime.

Restaging app rabbitmq in org system / space dev as admin...
...
name:              rabbitmq
requested state:   started
routes:            rabbitmq.run.codex2.starkandwayne.com
last uploaded:     Thu 20 Oct 12:48:08 UTC 2022
stack:             cflinuxfs3
buildpacks:        
        name             version   detect output   buildpack name
        ruby_buildpack   1.8.47    ruby            ruby

type:           web
sidecars:       
instances:      1/1
memory usage:   256M
     state     since                  cpu    memory          disk          logging      details
#0   running   2022-10-20T12:48:17Z   0.2%   33.8M of 256M   91.4M of 1G   0/s of 0/s
```

We are now ready to run our tests and verify that the service and its features are available to the application.

# <a name="testing"></a>Rabbitmq Testing

We saw that everything went fine so far, but unless we take that in good faith we can't really confirm that the application and the service is working as expected. Given that `good faith` is rarely something we rely on, lets go ahead and see for ourselves:

## Successful binding

[cf-rabbitmq-example-app](https://github.com/itsouvalas/cf-rabbitmq-example-app) has an endpoint to test exactly that. As per the readme:


`export APP=https://rabbitmq.run.codex2.starkandwayne.com`

`curl $APP/ping -k`

```
OK
```

But, running this application and using this endpoint is not a requirement to check a successful binding. If you have your application deployed already, you can ssh to the application and confirm the values for VCAP_SERVICES:

`cf ssh rabbitmq`

```
vcap@9e804020-4fd4-4207-5343-cbc1:~$
```

`env`

```json
VCAP_SERVICES={"rabbitmq":[{
  "label": "rabbitmq",
  "provider": null,
  "plan": "single-node",
  "name": "rmqsmall",
  "tags": [
    "blacksmith",
    "dedicated",
    "rabbitmq"
  ],
  "instance_guid": "0de041e6-91ba-4f55-b50f-d575ce91e2a5",
  "instance_name": "rmqsmall",
  "binding_guid": "514b628f-d92c-49d9-8575-d1e85f1e3d26",
  "binding_name": null,
  "credentials": {
    "api_url": "https://rabbitmq-single-node-0de041e6-91ba-4f55-b50f-d575ce91e2a5.system.codex2.starkandwayne.com/api",
    "dashboard_url": "https://rabbitmq-single-node-0de041e6-91ba-4f55-b50f-d575ce91e2a5.system.codex2.starkandwayne.com/#/login/mlaZOgWgLdF3xIZhqJIdMBfkQZx6tcwvGaLtTPAMeATyGiP7MAXFpJrvRQzZNg7i/cBDOZq6RorSRs7FHe9IYBMdlsKUopkEjzGWSfJAHFyAqlSgaRa8bRPh6gVEskXY7",
    "host": "10.7.16.17",
    "hostname": "10.7.16.17",
    "hostnames": [
      "10.7.16.17"
    ],
    "mgmt_port": 15672,
    "monitoring_password": "PKKCAfDCIp42mzk1OkF7yUoaOGRI8g5sVgmRYkG1CHBsrxLDCdNa76vrLzzk5aTn",
    "monitoring_username": "Q3rDM0aRKbCwaajmizfgRodj07RVLAK4tZggh650U9a7Lgo8XdESbUCZrvHRRUpb",
    "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
    "protocols": {
      "amqp": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "port": 5672,
        "ssl": false,
        "uri": "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671",
        "uris": [
          "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU",
        "vhost": "0de041e6-91ba-4f55-b50f-d575ce91e2a5"
      },
      "amqps": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "port": 5671,
        "ssl": true,
        "uri": "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671",
        "uris": [
          "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU",
        "vhost": "0de041e6-91ba-4f55-b50f-d575ce91e2a5"
      },
      "management": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "path": "/api",
        "port": 15672,
        "ssl": false,
        "uri": "http://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15672/api",
        "uris": [
          "http://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15672/api"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU"
      },
      "management_tls": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "path": "/api",
        "port": 15671,
        "ssl": true,
        "uri": "https://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15671/api",
        "uris": [
          "https://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15671/api"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU"
      }
    },
    "rmq_port": 5672,
    "tls_mgmt_port": 15671,
    "tls_port": 5671,
    "uri": "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671",
    "uris": [
      "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671"
    ],
    "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU",
    "vhost": "0de041e6-91ba-4f55-b50f-d575ce91e2a5"
  },
  "syslog_drain_url": null,
  "volume_mounts": [

  ]
}]}
```

## <a name="service-key"></a>Service key creation

Blacksmith uses the same `bind` function to bind the credentials seen earlier to a service key to be used outside that specific application:

`cf create-service-key rmqsmall rmqappuser`

```
Creating service key rmqappuser for service instance rmqsmall as admin...
OK
```

we may then confirm the same VCAP_SERVICES contents under the service key:

`cf service-key rmqsmall rmqappuser`

```yml
{
  "credentials": {
    "api_url": "https://rabbitmq-single-node-0de041e6-91ba-4f55-b50f-d575ce91e2a5.system.codex2.starkandwayne.com/api",
    "dashboard_url": "https://rabbitmq-single-node-0de041e6-91ba-4f55-b50f-d575ce91e2a5.system.codex2.starkandwayne.com/#/login/mlaZOgWgLdF3xIZhqJIdMBfkQZx6tcwvGaLtTPAMeATyGiP7MAXFpJrvRQzZNg7i/cBDOZq6RorSRs7FHe9IYBMdlsKUopkEjzGWSfJAHFyAqlSgaRa8bRPh6gVEskXY7",
    "host": "10.7.16.17",
    "hostname": "10.7.16.17",
    "hostnames": [
      "10.7.16.17"
    ],
    "mgmt_port": 15672,
    "monitoring_password": "PKKCAfDCIp42mzk1OkF7yUoaOGRI8g5sVgmRYkG1CHBsrxLDCdNa76vrLzzk5aTn",
    "monitoring_username": "Q3rDM0aRKbCwaajmizfgRodj07RVLAK4tZggh650U9a7Lgo8XdESbUCZrvHRRUpb",
    "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
    "protocols": {
      "amqp": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "port": 5672,
        "ssl": false,
        "uri": "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671",
        "uris": [
          "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU",
        "vhost": "0de041e6-91ba-4f55-b50f-d575ce91e2a5"
      },
      "amqps": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "port": 5671,
        "ssl": true,
        "uri": "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671",
        "uris": [
          "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU",
        "vhost": "0de041e6-91ba-4f55-b50f-d575ce91e2a5"
      },
      "management": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "path": "/api",
        "port": 15672,
        "ssl": false,
        "uri": "http://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15672/api",
        "uris": [
          "http://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15672/api"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU"
      },
      "management_tls": {
        "host": "10.7.16.17",
        "password": "0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD",
        "path": "/api",
        "port": 15671,
        "ssl": true,
        "uri": "https://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15671/api",
        "uris": [
          "https://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:15671/api"
        ],
        "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU"
      }
    },
    "rmq_port": 5672,
    "tls_mgmt_port": 15671,
    "tls_port": 5671,
    "uri": "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671",
    "uris": [
      "amqps://SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU:0AwkpvZT0zjxJ6YyDLhW6FZ80wuXM8SHytTnW6WIXOJHlal4TdMTbyb4cl3uJ7ZD@10.7.16.17:5671"
    ],
    "username": "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU",
    "vhost": "0de041e6-91ba-4f55-b50f-d575ce91e2a5"
  }
}
```

and we may monitor the service keys created using cf:

`cf service-keys rmqsmall`

```
Getting keys for service instance rmqsmall as admin...

name         last operation     message
rmqappuser   create succeeded   
```

## Successful messaging

We've confirmed the binding and the creation of the service key, but we have yet to see queues being created and messages beings posted and consumed. Let's go ahead and use the same application for a confirmation:

* Export the APP url (if not done already)

`export APP=https://rabbitmq.run.codex2.starkandwayne.com`

* Create a `dummy_queue`

`curl -X POST $APP/queues -d 'name=dummy_queue' -k`

```
SUCCESS
```

* List the available queues

`curl -X GET $APP/queues -k`

```
dummy_queue
```

* Say "hello"

`curl -X PUT $APP/queue/dummy_queue -d 'data=Hello' -k`

```
SUCCESS
```

* and receive the message
`curl -X GET $APP/queue/dummy_queue -k`

```
Hello
```

## <a name="permissions"></a>Permissions

With everything working we know that we have enough privileges to reach out to the deployed service, but since seeing is believing lets go ahead and take a look:

* ssh to the rabbitmq deployed instance:

`cd blacksmith-deployments` # or to any genesis deployment directory

get a listing of the available vms

`genesis -A bosh dev vms` # replace with your environment name file

```
Deployment 'rabbitmq-single-node-0de041e6-91ba-4f55-b50f-d575ce91e2a5'

Instance                                         Process State  AZ  IPs         VM CID               VM Type                     Active  Stemcell  
standalone/6271104d-30d9-4175-9222-cc9f12c2432d  running        z1  10.7.16.17  i-0a90c9519bad73d9b  blacksmith-rabbitmq-medium  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  
```

ssh using the deployment and instance name

`genesis -A bosh dev -d rabbitmq-single-node-0de041e6-91ba-4f55-b50f-d575ce91e2a5 ssh standalone/6271104d-30d9-4175-9222-cc9f12c2432d`

```
...
standalone/6271104d-30d9-4175-9222-cc9f12c2432d:~$
```

* export/source environment variables required to interact with `rabbitmqctl`

`source /var/vcap/jobs/rabbitmq/env`

`export RABBITMQ_ERLANG_COOKIE='insecure-erlang-cookie'`

* list users

`rabbitmqctl list_users`

```
Listing users ...
user    tags
mlaZOgWgLdF3xIZhqJIdMBfkQZx6tcwvGaLtTPAMeATyGiP7MAXFpJrvRQzZNg7i        [administrator]
SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU        [management policymaker]
Q3rDM0aRKbCwaajmizfgRodj07RVLAK4tZggh650U9a7Lgo8XdESbUCZrvHRRUpb        [monitoring]
```

* list permissions tied to our application user bound to our application or service key

`rabbitmqctl list_user_permissions SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU`

```
Listing permissions for user "SSUCXRozD25GG0tCFxMmWA9LWR5eBcNHjDjnaA14rkeLjNY8FGTJf6i85BMXxUeU" ...
vhost   configure       write   read
0de041e6-91ba-4f55-b50f-d575ce91e2a5    .*      .*      .*
```

From the list of the available users, we can also see a user with the `monitoring` tag attached to it, which can also be found under `monitoring_username` of VCAP_SERVICES:

`rabbitmqctl list_user_permissions Q3rDM0aRKbCwaajmizfgRodj07RVLAK4tZggh650U9a7Lgo8XdESbUCZrvHRRUpb`

```
Listing permissions for user "Q3rDM0aRKbCwaajmizfgRodj07RVLAK4tZggh650U9a7Lgo8XdESbUCZrvHRRUpb" ...
vhost   configure       write   read
0de041e6-91ba-4f55-b50f-d575ce91e2a5    ^$      ^$      .*
```

Finally, we also see a user attached to the `administrator` tag, though it hasn't been seen anywhere through the binding process:

```
Listing permissions for user "mlaZOgWgLdF3xIZhqJIdMBfkQZx6tcwvGaLtTPAMeATyGiP7MAXFpJrvRQzZNg7i" ...
vhost   configure       write   read
0de041e6-91ba-4f55-b50f-d575ce91e2a5    .*      .*      .*
```

This user is only available through blacksmiths UI, minimizing in that way the permissions available to the applications interacting with rabbitmq service. We will circle back on that on the monitoring section of this document.

# Autoscaling based on queue depth

Autoscaling might be considered one of the main reasons for taking advantage of a cloud infrastructure. 
[cf-app-autoscaler-genesis-kit](https://github.com/genesis-community/cf-app-autoscaler-genesis-kit) uses [
app-autoscaler-release](https://github.com/cloudfoundry/app-autoscaler-release) to scale up based on a number of metrics or schedules. Blacksmith's rabbitmq forge has been extended with [rabbitmq-metrics-emitter-release](https://github.com/starkandwayne/rabbitmq-metrics-emitter-release) that uses the mechanics of app-autoscaler to scale your application based on the queue's depth as a metric.

## Prerequisites

As you might have guessed already, atuoscaling based on queue depth requires [cf-app-autoscaler-genesis-kit](https://github.com/genesis-community/cf-app-autoscaler-genesis-kit) to be deployed along your cf. It uses a number of secrets that are exported by the kit to communicate with loggregator, which then become actionable scaling events based on a policy defining the queue and the threshold for those events.

Assuming that your environment name is dev, once you have:

* deployed cf-app-autoscaler

`genesis deploy dev` # on cf-app-autoscaler-deployments directory

* registered the broker to your deployed cf

`genesis do dev bind-autoscaler`

* setup the the 'autoscaler' plugin to the cf cli

`genesis do dev setup-cf-plugin`

* and created the corresponding service

`cf create-service autoscaler autoscaler-free-plan autoscaler`

you should be able to see the service broker listed

`cf service-brokers`

```
Getting service brokers as admin...
name             url
dev-blacksmith   https://blacksmith.system.codex2.starkandwayne.com:443
autoscaler       https://autoscalerservicebroker.system.codex2.starkandwayne.com
```

and the recently created service as well

`cf services`

```
Getting service instances in org system / space dev as admin...

name         offering     plan                   bound apps   last operation     broker           upgrade available
autoscaler   autoscaler   autoscaler-free-plan                create succeeded   autoscaler       no
rmq-3        rabbitmq     three-node                          create succeeded   dev-blacksmith   no
rmqsmall     rabbitmq     single-node                         create succeeded   dev-blacksmith   no
```

You are now ready to create the autoscaling policy, bind it together to the autoscaling service and test scaling based on the queue's depth.

## Autoscaling policy

Autoscaling policies can be very intricate to cover your every need. In this case we will create the bare minimum to allow autoscaling based on queue depth. At the time of this writing, the metric collected is a combination of the `queue_name` (dynamic) separated by an underscore `_` from `messages_ready` (static). In the example below we scale up when `messages_ready` is greater than (>) one (1) and scale down when it is less than (<) two (2). We are also setting the minimum and maximum number of instances between one (1) and three (3) :

```json
{
    "instance_min_count": 1,
    "instance_max_count": 3,
    "scaling_rules": [
{
  "metric_type": "dummy_queue_messages_ready",
  "threshold": 1,
  "operator": ">",
  "adjustment": "+1"
},
{
  "metric_type": "dummy_queue_messages_ready",
  "threshold": 2,
  "operator": "<",
  "adjustment": "-1"
}
]
}
```

## Binding autoscaling policy based on queue depth

Assuming that you have named the above file as `test-policy.json` the following line will bind the application to the autoscaler service:

`cf bind-service rabbitmq autoscaler -c test-policy.json`

```
Binding service instance autoscaler to app rabbitmq in org system / space dev as admin...
OK

TIP: Use 'cf restage rabbitmq' to ensure your env variable changes take effect
```

# Autoscaling testing
Having successfully bound the application to the autoscaler service you are ready to push messages to the queue. Using the same application and `dummy_queue` defined above, we move onto adding messages to the queue

(Steps completed already)

`export APP=https://rabbitmq.run.codex2.starkandwayne.com`

`curl -X POST $APP/queues -d 'name=dummy_queue' -k`

`curl $APP/ping -k` 


* Send 3 `Hello` messages to the `dummy_queue`

`curl -X PUT $APP/queue/dummy_queue -d 'data=Hello' -k`
```
SUCCESS
```

* Make messages ready

Given that the messages reach rabbitmq in an unacknowledged state in this application, and taking into consideration that autoscaler is looking out for `messages_ready`, we need to either wait for 30 minutes or force them to become ready by restaging the application:

`cf restage rabbitmq`

* `watch` for scaling up events

`watch -c -n30 "cf autoscaling-history rabbitmq"`

```
Scaling Type            Status          Instance Changes        Time                            Action                                                                            Error     
dynamic                 succeeded       2->3                    2022-10-21T14:06:06Z            +1 instance(s) because dummy_queue_messages_ready > 1msgs for 120 seconds              
dynamic                 succeeded       1->2                    2022-10-21T14:00:06Z            +1 instance(s) because dummy_queue_messages_ready > 1msgs for 120 seconds 
```

* consume the messages

Given the application ia a testing one, when restaging it lost knowledge of the queue. Go ahead and re-create the queue, **multiple times** until you receive SUCCESS **for all the instances running** (i.e 3 SUCCESS for 3 instances). That way all of them are aware of the queue's name/existence.

`curl -X POST $APP/queues -d 'name=dummy_queue' -k`

```
SUCCESS
```

and then read the messages

`curl -X GET $APP/queue/dummy_queue -k`
```
Hello
Hello
Hello
```

* `watch` for scaling down events

`watch -c -n30 "cf autoscaling-history rabbitmq"`

```
Retrieving scaling event history for app rabbitmq...
Scaling Type            Status          Instance Changes        Time                            Action
                                                Error
dynamic                 succeeded       2->1                    2022-10-21T14:33:06Z            -1 instance(s) because dummy_queue
_messages_ready < 2msgs for 120 seconds
dynamic                 succeeded       3->2                    2022-10-21T14:27:06Z            -1 instance(s) because dummy_queue
_messages_ready < 2msgs for 120 seconds
dynamic                 succeeded       2->3                    2022-10-21T14:21:06Z            +1 instance(s) because dummy_queue
```

* `watch` for messages ready metrics

`watch -c -n30 "cf autoscaling-metrics rabbitmq dummy_queue_messages_ready"`

```
Retrieving aggregated dummy_queue_messages_ready metrics for app rabbitmq...
Metrics Name                    Value           Timestamp     
dummy_queue_messages_ready      0msgs           2022-10-21T14:22:06Z     
dummy_queue_messages_ready      1msgs           2022-10-21T14:21:26Z     
dummy_queue_messages_ready      2msgs           2022-10-21T14:20:46Z     
dummy_queue_messages_ready      3msgs           2022-10-21T14:20:06Z     
dummy_queue_messages_ready      3msgs           2022-10-21T14:19:26Z     
dummy_queue_messages_ready      3msgs           2022-10-21T14:18:46Z     
dummy_queue_messages_ready      3msgs           2022-10-21T14:18:06Z     
dummy_queue_messages_ready      2msgs           2022-10-21T14:17:26Z     
dummy_queue_messages_ready      1msgs           2022-10-21T14:16:46Z     
dummy_queue_messages_ready      0msgs           2022-10-21T14:16:06Z 
```

# Monitoring/UI

We've seen already how we can do everything through `genesis` and `cf` cli. Our ability to monitor, or control the service for rabbitmq specifically doesn't stop here. Both blacksmith and rabbitmq provide us with a UI that we can either use to view our deployed services and their corresponding information, or to take action through rabbitmq's management interface.

## Blacksmith's UI

If you used the `fqdn` parameter above, you can access using the URL https://fqdn which in our example it translates to https://blacksmith.system.codex2.starkandwayne.com. Else, you can use the `ip` parameter which in this case translates to  https://10.7.16.8 . When visited, it will prompt you for a user name and password which can be found when running `genesis info dev` on your blacksmith's deployment directory

`genesis info dev`

```
Verifying availability of vault 'codex2' (https://10.7.1.22)...ok


================================================================================

BLACKSMITH Deployment for Environment 'dev'
...
blacksmith web management UI
  web url:   https://10.7.16.8:443
  username:  blacksmith
  password:  somelongpassword
  clickable: https://blacksmith:somelongpassword@10.7.16.8:443


blacksmith catalog
  Service   Plans              Tags
  =======   =====              ====
  rabbitmq  large-single-node  blacksmith
            large-three-node   dedicated
            single-node        rabbitmq
            three-node
  
  redis     cache-large        blacksmith
            cache-medium       dedicated
            cache-small        redis
```

![blacksmith UI](assets/blacksmith.png)

On this page you are informed of:

* The available plans
* The deployed Service instances and their corresponding links for
  * manifest
  * creds
  * and logs pertaining to the services creation process
* And a generalized log for all of the services

## Rabbitmq Management UI

Using the `creds.yml` above we are presented with a plethora of information:

```yml
admin_password: longadministratoruserpassword
admin_username: longadministratoruserusername
api_url: https://rabbitmq-three-node-a24f14f3-b191-4c04-b1bc-2edb845faca6.system.codex2.starkandwayne.com/api
dashboard_url: https://rabbitmq-three-node-a24f14f3-b191-4c04-b1bc-2edb845faca6.system.codex2.starkandwayne.com/#/login/longadministratoruserusername/longadministratoruserpassword
hostname: 10.7.16.18
hostnames:
- 10.7.16.18
- 10.7.18.17
- 10.7.17.17
hosts:
- 10.7.16.18
- 10.7.18.17
- 10.7.17.17
mgmt_port: 15672
monitoring_password: longmonitoringuserpassword
monitoring_username: longmonitsinguserusername
... information omitted for brevity
``` 

Using the `dashboard_url` and by providing the `admin_password` and `admin_username` we are presented with the rabbitmq's management UI https://rabbitmq-three-node-a24f14f3-b191-4c04-b1bc-2edb845faca6.system.codex2

![Rabbitmq Management UI](assets/rabbitmq.png)

### Additonal infromation

* `- rabbitmq-dashboard-registration`

The `dashboard_url` url may provide either an IP or a dns based route registerd with cf. In order to provide the latter, a cloudfoundry deployment should be already present and the `- rabbitmq-dashboard-registration` feature should be selected on blacksmith's deployment manifest.

* `- rabbitmq-tls`

Communication to rabbitmq may be either done securely though 5671 and 15671 port for amqp and the managment interface or insecurely though 5672 and 15672 respectively. When `- rabbitmq-tls` frature is selected on blacksmith's deployment manifest the former will be true.

* `- rabbitmq-dual-mode`

With `- rabbitmq-tls` feature enabled you also have the option to anable `- rabbitmq-dual-mode` feature which will allow both protocols. A quick way to confirm which features are enabled, is to attempt to connect to any of the deployed rabbitmq instaces (the features are enabled deployment wide):

`cd blacksmith-deployments` # or to any genesis deployment directory

get a listing of the available vms

`genesis -A bosh dev vms` # replace with your environment name file

```
...
Deployment 'rabbitmq-large-single-node-c2394ffe-e20d-47cb-81a6-dae8ee18d914'

Instance                                         Process State  AZ  IPs         VM CID               VM Type                    Active  Stemcell  
standalone/5f4b61f4-0291-4b3d-a9ec-5c15279deff9  running        z1  10.7.16.18  i-07e791e1470196892  blacksmith-rabbitmq-large  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  

1 vms

Deployment 'rabbitmq-large-three-node-cd199b92-5140-4864-80e7-ff3479f11b40'

Instance                                   Process State  AZ  IPs         VM CID               VM Type                    Active  Stemcell  
node/20e76fc6-4a24-4ea8-aedd-a5375c2c6a18  running        z1  10.7.16.20  i-0a8fd9ea293fb69e4  blacksmith-rabbitmq-large  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  
node/92487055-16ef-4a91-876d-08eb8274c8b1  running        z3  10.7.18.18  i-0f2d165d39bf7e3ee  blacksmith-rabbitmq-large  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  
node/97e72b4c-4d2f-4d6c-bb39-483c76e44c41  running        z2  10.7.17.18  i-07fea6d499a9f2f22  blacksmith-rabbitmq-large  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  

3 vms

Deployment 'rabbitmq-single-node-9e3ea2d6-58ed-46e7-8e7e-725d3e68bd61'

Instance                                         Process State  AZ  IPs         VM CID               VM Type                     Active  Stemcell  
standalone/17c0b84e-cf85-4b3c-8e26-71641c509f4d  running        z1  10.7.16.17  i-0dbbf6194fc901903  blacksmith-rabbitmq-medium  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  

1 vms

Deployment 'rabbitmq-three-node-14ca92f8-5fa7-4938-acf2-7cd49fb6351a'

Instance                                   Process State  AZ  IPs         VM CID               VM Type                     Active  Stemcell  
node/44c790ba-cda5-4677-86c1-831fb49d6033  running        z3  10.7.18.17  i-052513a792fd2776b  blacksmith-rabbitmq-medium  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  
node/7b603695-105a-4791-a90b-074d1d5b3aaa  running        z1  10.7.16.19  i-0926139c56492602b  blacksmith-rabbitmq-medium  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  
node/d36ce8c9-40c2-49bb-8c99-61490c6d74f4  running        z2  10.7.17.17  i-023225ea319ca8eca  blacksmith-rabbitmq-medium  true    bosh-aws-xen-hvm-ubuntu-bionic-go_agent/1.61  

3 vms

Succeeded
```

`nc -zv 10.7.18.17 5671`

```
Connection to 10.7.18.17 5671 port [tcp/amqps] succeeded!
```

`nc -zv 10.7.18.17 5672`

```
Connection to 10.7.18.17 5672 port [tcp/amqp] succeeded!
```

# Dynamic Credentials

Our past implementation of credentials handling relied on the creation of three types of users, admin, monitoring, and application, all of which were created during the creation of the service instance itself. The monitoring and application users were available to each application bound to the service instance or to each service key created against that service. Even though an application could be unbound from the Rabbitmq service or have the service key deleted, given the static nature of the credentials, those would still be able to communicate with RabbitMQ untill that service instance was deleted.

The dynamic credentials feature extends the predefined static credentials with new, unique credentials created each time an applicaiton is bound to the RabbitMQ service or a service key is created against that same service. As a result, operators can rely on the static credentials for monitoring, application testing and administering the RabbitMQ service while relying on dynamic credentials for each of the application bindings or service keys created.

## Creating dynamic credentials

The process is now embeded to the [Binding the service](#binding) and [Service key creation](#service-key) process defined earlier.

## Testing dynamic credentials

For generalized tests of the service, if you haven't done so already, you can go through the [Rabbitmq Testing](testing) process.

## Confirming the dynamic nature of credentials

### Environment Variables

`cf env rabbitmq` # replace with the application name bound to rabbitm's service

```yaml
Getting env variables for app rabbitmq in org system / space dev as admin...
System-Provided:
VCAP_SERVICES: {
  "rabbitmq": [
    {
      "binding_guid": "2e5552dd-94da-4768-aeca-ffb664ebce86",
      "binding_name": null,
      "credentials": {
        "api_url": "https://rabbitmq-single-node-070318e0-bed8-4263-993e-1c3f5e8f1ec4.system.codex2.starkandwayne.com/api",
        "credential_type": "dynamic",
        "dashboard_url": "https://rabbitmq-single-node-070318e0-bed8-4263-993e-1c3f5e8f1ec4.system.codex2.starkandwayne.com/#/login/3EfZvJt0QOxtDZCQfcwsVvQqxv58w3S3T7tRIh408e96gCHHBrn7bviYjxzzHUO3/67vg3KdmZ7x79VjVod6yRtXpeQnn19ztGlP6uCNplXLSxGRzpy3mTo4pO9dFnC9g",
        "host": "10.7.16.22",
        "hostname": "10.7.16.22",
        "hostnames": [
          "10.7.16.22"
        ],
        "mgmt_port": 15672,
        "monitoring_password": "lDZNOqrHI4JSxPM70ARfiIpg0rDsgyHF4To05atzZhpUmmfCzWq5RSJDIIlLkHrO",
        "monitoring_username": "lDWzf3ickkteAKMoKE6yzYcv9AvNeUfSGW2GPTfuPV99EvDXjhxAUPeGkSQlZGEz",
        "password": "ca05e71d-f9d6-4743-9f56-9edb3dbdbff7",
        "protocols": {
          "amqp": {
            "host": "10.7.16.22",
            "password": "ca05e71d-f9d6-4743-9f56-9edb3dbdbff7",
            "port": 5672,
            "ssl": false,
            "uri": "amqp://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:5672",
            "uris": [
              "amqp://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:5672"
            ],
            "username": "2e5552dd-94da-4768-aeca-ffb664ebce86",
            "vhost": "070318e0-bed8-4263-993e-1c3f5e8f1ec4"
          },
          "amqps": {
            "host": "10.7.16.22",
            "password": "ca05e71d-f9d6-4743-9f56-9edb3dbdbff7",
            "port": 5671,
            "ssl": true,
            "uri": "amqps://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:5671",
            "uris": [
              "amqps://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:5671"
            ],
            "username": "2e5552dd-94da-4768-aeca-ffb664ebce86",
            "vhost": "070318e0-bed8-4263-993e-1c3f5e8f1ec4"
          },
          "management": {
            "host": "10.7.16.22",
            "password": "ca05e71d-f9d6-4743-9f56-9edb3dbdbff7",
            "path": "/api",
            "port": 15672,
            "ssl": false,
            "uri": "http://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:15672/api",
            "uris": [
              "http://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:15672/api"
            ],
            "username": "2e5552dd-94da-4768-aeca-ffb664ebce86"
          },
          "management_tls": {
            "host": "10.7.16.22",
            "password": "ca05e71d-f9d6-4743-9f56-9edb3dbdbff7",
            "path": "/api",
            "port": 15671,
            "ssl": true,
            "uri": "https://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:15671/api",
            "uris": [
              "https://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:15671/api"
            ],
            "username": "2e5552dd-94da-4768-aeca-ffb664ebce86"
          }
        },
        "rmq_port": 5672,
        "tls_mgmt_port": 15671,
        "tls_port": 5671,
        "uri": "amqps://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:5671",
        "uris": [
          "amqps://2e5552dd-94da-4768-aeca-ffb664ebce86:ca05e71d-f9d6-4743-9f56-9edb3dbdbff7@10.7.16.22:5671"
        ],
        "username": "2e5552dd-94da-4768-aeca-ffb664ebce86",
        "vhost": "070318e0-bed8-4263-993e-1c3f5e8f1ec4"
      },
      "instance_guid": "070318e0-bed8-4263-993e-1c3f5e8f1ec4",
      "instance_name": "rmqsmall",
      "label": "rabbitmq",
      "name": "rmqsmall",
      "plan": "single-node",
      "provider": null,
      "syslog_drain_url": null,
      "tags": [
        "blacksmith",
        "dedicated",
        "rabbitmq"
      ],
      "volume_mounts": []
    }
  ]
}


VCAP_APPLICATION: {
  "application_id": "00719e0c-dc66-40af-bf8f-90755bf374b0",
  "application_name": "rabbitmq",
  "application_uris": [
    "rabbitmq.run.codex2.starkandwayne.com"
  ],
  "cf_api": "https://api.system.codex2.starkandwayne.com",
  "limits": {
    "fds": 16384
  },
  "name": "rabbitmq",
  "organization_id": "0b383e89-cae5-4f98-bbd8-7a8a6e1296a0",
  "organization_name": "system",
  "space_id": "bacd79a6-9a65-4ffc-8349-b314883efd84",
  "space_name": "dev",
  "uris": [
    "rabbitmq.run.codex2.starkandwayne.com"
  ],
  "users": null
}



User-Provided:
RABBITMQ_USE_TLS: true

No running env variables have been set

No staging env variables have been set
```

Note the `"credential_type": "dynamic"` as well as the uuid based format for both `username` and `password` used for interacting with rabbitmq's service instance

### Service key

`cf service-key rmqsmall rmqappuser` # replace with the service and service key name used

```yaml
Getting key rmqappuser for service instance rmqsmall as admin...

{
  "credentials": {
    "api_url": "https://rabbitmq-single-node-070318e0-bed8-4263-993e-1c3f5e8f1ec4.system.codex2.starkandwayne.com/api",
    "credential_type": "dynamic",
    "dashboard_url": "https://rabbitmq-single-node-070318e0-bed8-4263-993e-1c3f5e8f1ec4.system.codex2.starkandwayne.com/#/login/3EfZvJt0QOxtDZCQfcwsVvQqxv58w3S3T7tRIh408e96gCHHBrn7bviYjxzzHUO3/67vg3KdmZ7x79VjVod6yRtXpeQnn19ztGlP6uCNplXLSxGRzpy3mTo4pO9dFnC9g",
    "host": "10.7.16.22",
    "hostname": "10.7.16.22",
    "hostnames": [
      "10.7.16.22"
    ],
    "mgmt_port": 15672,
    "monitoring_password": "lDZNOqrHI4JSxPM70ARfiIpg0rDsgyHF4To05atzZhpUmmfCzWq5RSJDIIlLkHrO",
    "monitoring_username": "lDWzf3ickkteAKMoKE6yzYcv9AvNeUfSGW2GPTfuPV99EvDXjhxAUPeGkSQlZGEz",
    "password": "4335fed9-299f-4c3a-b8dd-ee00dbab9f7a",
    "protocols": {
      "amqp": {
        "host": "10.7.16.22",
        "password": "4335fed9-299f-4c3a-b8dd-ee00dbab9f7a",
        "port": 5672,
        "ssl": false,
        "uri": "amqp://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:5672",
        "uris": [
          "amqp://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:5672"
        ],
        "username": "43eb6b37-dfa7-446d-9317-b4c2030cf777",
        "vhost": "070318e0-bed8-4263-993e-1c3f5e8f1ec4"
      },
      "amqps": {
        "host": "10.7.16.22",
        "password": "4335fed9-299f-4c3a-b8dd-ee00dbab9f7a",
        "port": 5671,
        "ssl": true,
        "uri": "amqps://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:5671",
        "uris": [
          "amqps://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:5671"
        ],
        "username": "43eb6b37-dfa7-446d-9317-b4c2030cf777",
        "vhost": "070318e0-bed8-4263-993e-1c3f5e8f1ec4"
      },
      "management": {
        "host": "10.7.16.22",
        "password": "4335fed9-299f-4c3a-b8dd-ee00dbab9f7a",
        "path": "/api",
        "port": 15672,
        "ssl": false,
        "uri": "http://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:15672/api",
        "uris": [
          "http://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:15672/api"
        ],
        "username": "43eb6b37-dfa7-446d-9317-b4c2030cf777"
      },
      "management_tls": {
        "host": "10.7.16.22",
        "password": "4335fed9-299f-4c3a-b8dd-ee00dbab9f7a",
        "path": "/api",
        "port": 15671,
        "ssl": true,
        "uri": "https://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:15671/api",
        "uris": [
          "https://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:15671/api"
        ],
        "username": "43eb6b37-dfa7-446d-9317-b4c2030cf777"
      }
    },
    "rmq_port": 5672,
    "tls_mgmt_port": 15671,
    "tls_port": 5671,
    "uri": "amqps://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:5671",
    "uris": [
      "amqps://43eb6b37-dfa7-446d-9317-b4c2030cf777:4335fed9-299f-4c3a-b8dd-ee00dbab9f7a@10.7.16.22:5671"
    ],
    "username": "43eb6b37-dfa7-446d-9317-b4c2030cf777",
    "vhost": "070318e0-bed8-4263-993e-1c3f5e8f1ec4"
  }
}
```

Again, note the `"credential_type": "dynamic"` as well as the uuid based format for both `username` and `password` used for interacting with rabbitmq's service instance.

### Rabbitmq instance

Each of those , `bind` and `service-key` commands has created the corresponding key to rabbitmq's instance. ssh to the rabbitmq instance ( discussed on [permissions](#permissions) earlier ) and list the users:

`rabbitmqctl list_users`

```json
Listing users ...
user    tags
UAmJaQMHpT3NEgF0hHRu3ztIhSq9BhrG1ffcNg86aruy54qBy5hNm799aKqalWqm        [management policymaker]
43eb6b37-dfa7-446d-9317-b4c2030cf777    [management, policymaker]
2e5552dd-94da-4768-aeca-ffb664ebce86    [management, policymaker]
lDWzf3ickkteAKMoKE6yzYcv9AvNeUfSGW2GPTfuPV99EvDXjhxAUPeGkSQlZGEz        [monitoring]
3EfZvJt0QOxtDZCQfcwsVvQqxv58w3S3T7tRIh408e96gCHHBrn7bviYjxzzHUO3        [administrator]
```

Note the uuid based format for each of the users created earlier, `2e5552dd-94da-4768-aeca-ffb664ebce86` for the binding and `43eb6b37-dfa7-446d-9317-b4c2030cf777` for the service key

### Deleting the dynamic credentials

* unbind the application

`cf unbind-service rabbitmq rmqsmall`

```
Unbinding app rabbitmq from service rmqsmall in org system / space dev as admin...
OK
```

* delete the service key

`cf delete-service-key rmqsmall rmqappuser`

```
cf delete-service-key rmqsmall rmqappuser
Really delete the service key rmqappuser? [yN]: y
Deleting key rmqappuser for service instance rmqsmall as admin...
OK
```

### Confirming cleanup

Repeat the `list_users` command issued earlier on the rabbitmq instance

`rabbitmqctl list_users`

```
Listing users ...
user    tags
UAmJaQMHpT3NEgF0hHRu3ztIhSq9BhrG1ffcNg86aruy54qBy5hNm799aKqalWqm        [management policymaker]
lDWzf3ickkteAKMoKE6yzYcv9AvNeUfSGW2GPTfuPV99EvDXjhxAUPeGkSQlZGEz        [monitoring]
3EfZvJt0QOxtDZCQfcwsVvQqxv58w3S3T7tRIh408e96gCHHBrn7bviYjxzzHUO3        [administrator]
```

and confirm that the uuid based users are no longer present.

## Conclusion

If everything went as planned and assuming that you followed along, by the time your reach these lines you have managed to 
* deploy rabbitm's forge through blacksmith's genesis kit, 
* create and bind rabbitmq service to a testing application, 
* test connectivity, queue creation as well as message creation and consumption
* create and bind an autoscaling policy to the test application
* test autoscaling based on rabbitm's quees depth.
* had fun during the process!

Finally, you also saw a bit under the hood which will give you a head start in the (hopefully unlikely) event of having to troubleshoot your deployment. Happy messaging!