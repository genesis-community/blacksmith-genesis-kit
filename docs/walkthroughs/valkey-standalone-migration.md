# Migrating from Redis to Valkey Standalone

This guide walks through migrating a Cloud Foundry application from a
Blacksmith-managed Redis service instance to a Valkey standalone instance
using live replication to achieve near-zero data loss.

## Prerequisites

- BOSH CLI access with permissions to SSH into deployments
- CF CLI authenticated with space developer permissions
- A running Redis service instance with data to migrate
- A Valkey standalone service instance provisioned via Blacksmith

## Test Application

### App Location

`~/ocfp/apps/apps/cf-redis-example-app`

## Push Application

```bash
cf push redis-example-app
```

## Create Services

```bash
cf cs redis cache-small redis-test
cf cs valkey standalone-8 valkeys8
```

## Bind to Redis

```bash
cf bs redis-example-app redis-test
cf restage redis-example-app
```

## Export App Route

```bash
# use cf app redis-example-app to find the route and grep it out
export APP=https://$(cf app redis-example-app | grep routes: | awk '{print $2}')

# or manually set it to the route you see in the output of `cf app redis-example-app`
export APP=https://redis-example-app.apps.aws.lab.fivetwenty.io
```

## Populate with Some Data

```bash
curl -X PUT $APP/foo -d 'data=bar'
curl -X PUT $APP/hello -d 'data=world'
curl -X PUT $APP/number -d 'data=42'
curl -X PUT $APP/name -d 'data=redis'
curl -X PUT $APP/language -d 'data=cloudfoundry'
```

## Retrieve Data Before Migration

```bash
curl -X GET $APP/foo
curl -X GET $APP/hello
curl -X GET $APP/number
curl -X GET $APP/name
curl -X GET $APP/language
```


## Create Service Key for Redis

```bash
cf create-service-key redis-test redis-test-key
# retrieve the service key credentials
cf service-key redis-test redis-test-key
```

## Get Valkey BOSH Deployment

```bash
export VALKEY_DEPLOYMENT=$(bosh deps | grep valkey-standalone-8 | awk '{print $1}')
```

## SSH to the Valkey Instance

```bash
bosh -d $VALKEY_DEPLOYMENT ssh
```

## Disable CONFIG Command Restriction

```bash
# identify the configuration file path and comment out the
# `rename-command CONFIG ""` line to allow the CONFIG command
export CONFIG_FILE=$(ps -ef | grep valkey | grep -v grep | head -n 1  | awk '{print $NF}')
sed -i '/^rename-command CONFIG ""/s/^/#/' $CONFIG_FILE

# restart valkey to apply the changes
monit restart standalone-8
```

## Configure Replication

```bash
export REDIS_HOST=<redis-host-from-service-key>
# use getent to get the ip of the redis host
getent hosts $REDIS_HOST | awk '{print $1}'

# enter the redis cli on the valkey instance using the password from the config file
redis -p 6379 -a $(cat $CONFIG_FILE | grep requirepass | awk '{print $2}')
```

Configure valkey to replicate from redis. Replace `<redis-host>`, `<redis-port>`,
and `<redis-password>` with the values from the redis service key credentials,
using the getent output for the host ip.

```redis-cli
REPLICAOF <redis-host> <redis-port>
CONFIG SET masterauth <redis-password>
```

Verify the data is being replicated to valkey:

```redis-cli
get foo
get hello
get number
get name
get language
```


## Switch Application to Valkey

```bash
cf bs redis-example-app valkeys8

# unbind from redis
cf us redis-example-app redis-test

# stop the app so that no more writes are sent to the old master
cf stop redis-example-app
```

## Promote Valkey to Master

```redis-cli
REPLICAOF NO ONE
INFO replication
exit
```

## Reinstate CONFIG Restriction and Restart

```bash
sed -i '/^#rename-command CONFIG ""/s/^#//' $CONFIG_FILE
monit restart standalone-8
```

## Restage and Verify

```bash
cf restage redis-example-app

# verify data is accessible via valkey
curl -X GET $APP/foo
curl -X GET $APP/hello
curl -X GET $APP/number
curl -X GET $APP/name
curl -X GET $APP/language
```

## Cleanup Old Redis Service

```bash
cf delete-service-key redis-test redis-test-key -f
cf ds redis-test -f
```

## Troubleshooting

if on pushing data you receive 

`<h1>Internal Server Error</h1>`

* first make sure you have **restaged the app** after binding to the service. 
* If you have restaged and are still receiving this error, check the logs for the app with `cf logs redis-example-app --recent` and look for any errors related to connecting to the Redis service.