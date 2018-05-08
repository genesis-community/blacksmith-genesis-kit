# Improvements

- All three forges (redis, rabbitmq, and postgresql) now have
  dedicated properties for setting service-level catalog metadata,
  like display name, description, and tags.

# New Features

- A new subkit / feature, `mariadb` has been added to allow
  deployment of standalone MariaDB instances.  This is
  experimental at this stage, while we work towards clustering and
  other production-level features.
