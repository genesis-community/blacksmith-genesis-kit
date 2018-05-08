# Improvements

- All three forges (redis, rabbitmq, and postgresql) now have
  dedicated properties for setting service-level catalog metadata,
  like display name, description, and tags.

- **Blacksmith** has been upgraded from to 0.0.9 (BOSH release
  0.0.5) - see the [release notes][1] for more details.

[1]: https://github.com/cloudfoundry-community/blacksmith/releases/tag/v0.0.9

# New Features

- A new subkit / feature, `mariadb` has been added to allow
  deployment of standalone MariaDB instances.  This is
  experimental at this stage, while we work towards clustering and
  other production-level features.
