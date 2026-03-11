# Migrating from Redis Cluster to Valkey Cluster

This guide walks through migrating data from a Blacksmith-managed Redis
cluster to a Valkey cluster using
[RedisShake](https://github.com/tair-opensource/RedisShake) for
cluster-to-cluster data migration.

Unlike standalone instances, Redis/Valkey clusters cannot use `REPLICAOF`
for live replication across clusters, and `redis-cli --cluster import`
does not support cluster sources. RedisShake handles cluster topology
automatically, syncing data from all source masters to the destination.

## Prerequisites

- CF CLI authenticated with space developer permissions
- `redis-cli` available (installed on the jumpbox or BOSH VMs)
- [RedisShake v4.5.0+](https://github.com/tair-opensource/RedisShake/releases)
  installed on the jumpbox
- A healthy Redis cluster service instance with data to migrate
- A healthy Valkey cluster service instance provisioned via Blacksmith

## Install RedisShake

```bash
curl -L -o redis-shake.tar.gz \
  https://github.com/tair-opensource/RedisShake/releases/download/v4.5.0/redis-shake-v4.5.0-linux-amd64.tar.gz
tar xzf redis-shake.tar.gz
cp redis-shake-v4.5.0-linux-amd64/redis-shake .
./redis-shake -v
```

## Create Services

```bash
cf cs redis cache-cluster-small redis-cluster-test
cf cs valkey cluster-8 valkey-cluster-test
```

## Populate Source Cluster with Test Data

Use `redis-cli -c` (cluster mode) to write test data directly. The `-c`
flag handles `MOVED` redirects automatically, ensuring keys land on the
correct master regardless of slot assignment.

```bash
# Get credentials from the service key
cf create-service-key redis-cluster-test redis-cluster-key
cf service-key redis-cluster-test redis-cluster-key

export REDIS_HOST=<redis-host-ip>
export REDIS_PORT=6379
export REDIS_PASS=<redis-password>

# Write test data (use -c for cluster mode)
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" SET foo bar
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" SET hello world
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" SET number 42
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" SET name redis
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" SET language cloudfoundry
```

## Verify Data Before Migration

```bash
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" GET foo
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" GET hello
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" GET number
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" GET name
redis-cli -c -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" GET language
```

> **Note:** The `cf-redis-example-app` from pivotal-cf uses a single-node
> Redis client (`Redis.new`) which does not handle cluster `MOVED` redirects.
> Keys that hash to a different master's slot range will return
> `Internal Server Error`. Use `redis-cli -c` for cluster testing instead.

## Get Valkey Service Credentials

```bash
cf create-service-key valkey-cluster-test valkey-cluster-key
cf service-key valkey-cluster-test valkey-cluster-key

export VALKEY_HOST=<valkey-host-ip>
export VALKEY_PORT=6379
export VALKEY_PASS=<valkey-password>
```

## Verify Cluster Health

Confirm both clusters are healthy before proceeding.

```bash
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASS" cluster info
redis-cli -h $VALKEY_HOST -p $VALKEY_PORT -a "$VALKEY_PASS" cluster info
```

Both should show `cluster_state:ok` with all 16384 slots assigned.

## Migrate Data with RedisShake

Create a `shake.toml` configuration file. RedisShake only needs one node
address per cluster — it discovers the full topology automatically.

```bash
cat > shake.toml << EOF
[sync_reader]
cluster = true
address = "$REDIS_HOST:$REDIS_PORT"
password = "$REDIS_PASS"
tls = false
sync_rdb = true
sync_aof = false

[redis_writer]
cluster = true
address = "$VALKEY_HOST:$VALKEY_PORT"
password = "$VALKEY_PASS"
tls = false

[advanced]
rdb_restore_command_behavior = "rewrite"
EOF
```

## Stop the application

At this point we are ready to migrate the data from the redis cluster to the valkey cluster. Before you do you have to stop the aplication so that no new data gets introduced until the migration is complete.



## Run the migration:

```bash
./redis-shake shake.toml
```

- `sync_rdb = true` — performs full data sync via RDB snapshot
- `sync_aof = false` — skips incremental replication (one-time copy)
- `rdb_restore_command_behavior = "rewrite"` — overwrites existing keys

## Verify Data on Valkey

```bash
redis-cli -c -h $VALKEY_HOST -p $VALKEY_PORT -a "$VALKEY_PASS" GET foo
redis-cli -c -h $VALKEY_HOST -p $VALKEY_PORT -a "$VALKEY_PASS" GET hello
redis-cli -c -h $VALKEY_HOST -p $VALKEY_PORT -a "$VALKEY_PASS" GET number
redis-cli -c -h $VALKEY_HOST -p $VALKEY_PORT -a "$VALKEY_PASS" GET name
redis-cli -c -h $VALKEY_HOST -p $VALKEY_PORT -a "$VALKEY_PASS" GET language
```

## Unbind/Bind redis to valkey

With the data confirmed you are ready to unbind the redis cluster and rebind the application to the valkey cluster.

## Cleanup

```bash
# remove service keys
cf delete-service-key redis-cluster-test redis-cluster-key -f
cf delete-service-key valkey-cluster-test valkey-cluster-key -f

# remove old redis service
cf ds redis-cluster-test -f
```

## Troubleshooting

### Cluster State Fail / Nodes Not Discovering Each Other

If `cluster info` shows `cluster_state:fail` and `cluster_known_nodes:1`,
the cluster gossip protocol is not working.

Check the `CLUSTER NODES` output for the bus port:

```bash
redis-cli -h $HOST -p $PORT -a "$PASS" CLUSTER NODES
```

If you see `:6379@26379` (bus port 26379), the cluster has TLS dual-mode
enabled. The bus port is calculated as `tls-port + 10000` (16379 + 10000
= 26379). Verify the bus port is reachable between nodes:

```bash
nc -zv <other-node-ip> 26379
```

If the `CLUSTER MEET` command in the post-deploy script uses port 6379,
the cluster will try bus port 16379 (6379 + 10000) instead of 26379,
causing nodes to never discover each other. The fix is to use the TLS
port (16379) in the CLUSTER MEET command when TLS dual-mode is enabled.

### Cluster Health Issues

If `cluster info` shows `cluster_state:fail` but nodes are known, check
slot assignment:

```bash
redis-cli -c -h $HOST -p $PORT -a "$PASS" CLUSTER NODES
```

All nodes should be visible and slots fully assigned (0-16383). If nodes
are missing or slots are unassigned, the cluster needs to be repaired
before migration can proceed.
