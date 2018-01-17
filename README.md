blacksmith Genesis Kit
=================

FIXME: The kit author should have filled this in with details about
what this is, and what it provides. But they have not, and that is sad.
Perhaps a GitHub issue should be opened to remind them of this?

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

Subkits
-------

FIXME: The kit author should have filled this in with details
about what subkits are defined, and how they affect the deployment. But they
have not, and that is sad. Perhaps a GitHub issue should be opened to remind
them of this?

Params
------

FIXME: The kit author should have filled this in with details about the params
present in the base kit, as well as each subkit defined. These should likely
be in different sections (one for base, one per subkit). Unfortunately,
the author has not done this, and that is sad. Perhaps a GitHub issue
should be opened to remind them of this?

Cloud Config
------------

FIXME: The kit author should have filled in this section with details about
what cloud config definitions this kit expects to see in play and how to
override them. Also useful are hints at default values for disk + vm sizing,
scaling considerations, and other miscellaneous IaaS components that the deployment
might require, like load balancers.

