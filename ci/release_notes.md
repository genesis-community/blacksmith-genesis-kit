# Software Updates

- Bumped Stemcells to Xenial v621.55
- Bumped PostgreSQL forge for standalone from 0.2.1 to 0.3.0 (PostgreSQL 9.5.20)
  The clustered PostgreSQL will continue to use PostgreSQL forge 2.0.0
- Bumped Redis Forge from 0.4.0 to 0.4.1 (Redis 5.0.6 to 5.0.7)
- Bumped RabbitMQ Forge from 0.2.0 to 0.3.0 (RabbitMQ to 3.7.23 and Erlang to 21.3)
- Bumped MariaDB forge to 0.4.0, including MariaDB 10.4.12, and
  has the change from 0.3.0 to provides a default database
  for applications (particularly COTS packaged apps) that are too
  timid to just login as root and create their own.

When updating to Blacksmith-genesis-kit 0.6.0 please ensure your compilation VM has 
a 16GB (or larger disk).  On a 8GB disk, the MariaDB forge may run out of space 
compiling and fail creating new MariaDB services.  (We recommend 4vCPU, 8GB RAM, 16GB disk) 
