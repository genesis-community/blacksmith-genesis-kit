# Changelog

## v1.4.0

This release moves the Blacksmith BOSH release to 2.5.0, turns on CredHub cleanup of deprovisioned service instances by default for external directors, and takes the bosh CLI out of the kit's hooks. It also adds an opt-in `resolute` feature and a `cf-haproxy-ca` feature. In addition, it fixes several problems that left forge service instances unable to deploy or deploying without TLS.

### Upgrading

- **Blacksmith BOSH release 2.5.0**

  The kit now pins blacksmith-boshrelease 2.5.0, which bumps the broker to v1.6.0. The broker no longer embeds the bosh CLI and talks to the director only through the director's REST API. The release now requires `bosh.ca_cert` and refuses to render its config without it, but kit users don't need to set anything, because the kit sets it from the director's CA in its default mode and from `params.external_bosh.cacert` in external mode. A test in the kit now refuses any blacksmith pin older than 2.5.0. The release also turns CredHub cleanup on by default in dry-run mode, quotes the values it writes into the broker config, and gives up on a BOSH task it cannot read for six hours. The full list is in the release notes at https://github.com/blacksmith-community/blacksmith-boshrelease/releases/tag/v2.5.0.

- **CredHub cleanup needs a BOSH kit release that does not exist yet**

  For an external director, which means an environment that uses `external-bosh` or `ocfp`, CredHub cleanup is now on by default. It reads its CredHub URL, client ID, client secret, CA, and director name from the director's exodus record at `<env>/bosh`. The CredHub URL comes from the director's `credhub` addon, which BOSH kit v4.1.0 already publishes. The other four keys are published only when the director uses its `blacksmith-integration` feature, and that change is on the BOSH kit's develop branch and in no BOSH kit release. The latest BOSH kit release is v4.1.0, which does not have it. Until a BOSH kit release newer than v4.1.0 ships and we redeploy the director with it, a deploy of this kit warns and names each missing key, the kit wires no CredHub connection, and the broker deletes nothing from CredHub. Nothing else about the deploy fails. Once the keys exist, we redeploy the director and then redeploy Blacksmith. We can also silence the warning by adding the `skip-credhub-cleanup` feature, which turns cleanup off.

- **CredHub cleanup starts in dry-run mode**

  When the wiring is complete, the sweep for orphaned variables only logs what it would delete. The broker deletes nothing in the sweep until we set `params.credhub_cleanup.sweep` to `delete`. The accepted values are `off`, `dry-run`, and `delete`, and while the wiring is on, the kit rejects anything else when it builds the blueprint. An internal director has no CredHub, so the kit leaves cleanup disabled for it.

- **The default stemcell is now ubuntu-noble**

  The default for `params.stemcell_os` moves from `ubuntu-jammy` to `ubuntu-noble` for the broker VM, in both the base manifest and the OCFP defaults. Valkey forge service instances move as well, by a different route. The valkey-forge release we pinned at v1.3.0 hardcoded jammy in its plan templates, and the kit passed it nothing. The kit now passes `params.stemcell_os` to the forge, and that parameter defaults to `ubuntu-noble`. An environment that relied on the old default and still wants jammy has to set `params.stemcell_os` itself.

- **The kit no longer runs the bosh CLI**

  None of the kit's hooks or manifests run the bosh CLI any more, so the pre-deploy hook no longer needs it on the host that runs `genesis deploy`. Genesis itself still uses the bosh CLI to deploy. The pre-deploy hook now reads the manifest with Genesis's own YAML loader instead of running `bosh int` and `spruce json`. When the manifest fails to load, the error names the manifest path and the likely cause, which is a file that is not valid YAML.

- **The bosh addon prints exports instead of logging in**

  `genesis do <env> bosh` no longer creates a BOSH alias or logs in. It prints shell `export` lines for `BOSH_ENVIRONMENT`, `BOSH_CA_CERT`, `BOSH_CLIENT`, and `BOSH_CLIENT_SECRET`, and runs no command. We use it as `eval "$(genesis do <env> bosh)"`, and then run the bosh CLI ourselves when the broker is not answering. The output holds the director's client secret. The addon reads `bosh_address`, `bosh_cacert`, `bosh_username`, and `bosh_password` from the exodus record, and it names any missing key along with the exodus path.

- **The SHIELD import goes through Genesis**

  The pre-deploy hook now merges the SHIELD import template with the hook's `spruce_merge` instead of a process substitution. When the merge fails, the import stops and the error names the template and the merge error. The merged document holds the SHIELD password, so the hook writes it to a temporary file with mode 0600, passes that file to `shield import`, and removes it whether or not the import succeeds. The `shield` CLI is still needed for that step.

- **Post-deploy advice and docs point at the broker API**

  The next-steps text no longer suggests `do visit`, which has no addon, and it no longer lists a step for reaching the internal director. It now suggests `do open` for the web UI, and it suggests the curl addon for `/b/tasks` and `/b/blacksmith/vms`, for example `genesis do <env> -- curl /b/tasks`. We rewrote the manual, the guides, and the RabbitMQ walkthroughs the same way. Steps that have no broker route, such as director job logs, `cck`, deleting an orphaned deployment, and uploading a release by hand, now sit under sections that load the director's details with `eval` and present those commands as our own tooling.

- **Genesis 3.2.0 is the minimum for the cloud-config hook**

  The cloud-config hook now requires Genesis 3.2.0, up from 3.1.0, because the forge zone described below uses `az_cloud_properties`.

- **PVE bridge and storage no longer fall back to lab literals**

  The cloud-config hooks used to read `pve_network_bridge` and `pve_disk_storage` from `bosh-configs.cpi` in the environment file and otherwise fell back to the literals `lvnet001` and `zfs-1`. They now resolve each setting from the environment file, then from the OCFP vault config under `cpi/pve`, which `ocfp vault populate` writes, and then from the Proxmox defaults `vmbr0` and `local-lvm`. An environment that depended on the old literals has to set them in its environment file or in the vault config. The hook fails with guidance if the value it resolves is empty.

- **Forges in OCFP environments now get TLS on the next deploy**

  Listing `ocfp` before `redis`, `valkey`, or `rabbitmq` in the features list used to drop `redis-tls`, `valkey-tls`, `rabbitmq-tls`, and `rabbitmq-dashboard-registration` without any warning, so those forges deployed in plaintext. The kit now expands the `ocfp` sub-features whatever the list order, so the next deploy of such an environment adds the TLS blocks and changes the manifest.

### What's new

- **CredHub cleanup wiring**

  Besides the default described above, the new `skip-credhub-cleanup` feature turns cleanup off for an external director. A `credhub-cleanup` feature name does nothing, and an environment file that lists it still validates and gets a deprecation notice. The post-deploy hook now checks that the cleanup client can get a token from the director's UAA, using the secret from the exodus record. If that check fails, it warns, and it tells us to redeploy the director with the current BOSH kit release. That check never fails a successful deploy. The parameters `params.credhub_cleanup.url`, `ca_cert`, and `client_id` override the exodus values. The client secret and the director name have no override and always come from the exodus record.

- **The `cf-haproxy-ca` feature**

  With `cf-integration` or `ocfp`, the new feature hands the broker the CF deployment's self-signed haproxy CA for its CF API connection. It reads `vault_base` from the sibling CF deployment's exodus record and references `haproxy_ca:certificate` there, and Genesis entombs the certificate into this deployment's own CredHub scope. If the record or its `vault_base` is missing, the hook stops and names the CF deployment and the exodus path. The feature is refused without `cf-integration` or `ocfp`. We can still set `params.cf_cacert` to a PEM bundle, which wins over the vault reference, and `params.cf_skip_ssl_validation` controls certificate verification for that endpoint. Environments that do not name the feature get the CA from `params.cf_cacert`, which defaults to empty, and they get `skip_ssl_validation` from `params.cf_skip_ssl_validation`, which defaults to false.

- **The opt-in `resolute` feature**

  The feature deploys the broker VM on the `ubuntu-resolute` stemcell and pins the bpm release to 1.4.41, the first version that compiles on resolute. With `shield-agent` it also pins shield 9.4.1, and with `valkey` it pins valkey-forge 1.4.0, because shield 9.4.0 and earlier and valkey-forge 1.3.2 and earlier call `chpst`, which resolute does not ship. The kit refuses a `params.stemcell_os` other than `ubuntu-resolute` when the feature is on, and it refuses `ubuntu-resolute` when the feature is off. Without the feature the default stays `ubuntu-noble`. The manual has a new section on Ubuntu Resolute Stemcells, and the kit now has spec environments for the default and resolute stemcells.

- **Forge zone, network, and VM type for valkey**

  With the `valkey` feature, the cloud config now defines the bare names the valkey forge's default plans use, which are a `z1` zone and a `valkey-service` network. It also defines a `default` VM type, and it does that whether or not the `valkey` feature is on. The `z1` zone copies the cloud properties of one of the director's own zones, so on Proxmox the forge VMs inherit that zone's host pin. `params.forge_az` chooses the zone to copy. It accepts the short form such as `z2`, the full name such as `<env>-z2`, or the zone's key in the OCFP configuration, and it defaults to `z1`. The valkey cluster plan is pinned to `z1` to match.

- **Stemcell parameters reach the valkey forge**

  `params.stemcell_os` and `params.stemcell_version` now flow into the valkey forge's service instance deployments, which valkey-forge 1.2.0 had hardcoded to jammy and `latest` in its plan templates.

- **The services CA is seeded on deploy**

  The post-deploy hook now seeds `blacksmith_services_ca` into CredHub when the TLS features need it, so provisioning a service no longer fails with a CredHub 404 until someone runs the `register` addon. The broker's server certificate also carries `params.fqdn` as a SAN, so gorouter can validate it for registered routes.

- **Release pins**

  The blacksmith release moves from 2.3.0 to 2.5.0, with the intermediate versions 2.3.1, 2.3.4 through 2.3.10, and 2.4.0 along the way. Among them, 2.3.1 renders `bosh.ca_cert` into the broker config, and 2.3.4 packages a broker whose director client trusts that CA, so an external director with a private CA can verify. The forge pins move valkey-forge from 1.2.0 to 1.4.0, redis-forge from 1.4.2 to 1.4.4, and rabbitmq-forge from 1.5.0 to 1.5.1. Valkey-forge 1.4.0 adds a `ca_certificate` field to TLS valkey bindings. The forge releases render the stemcell version as a quoted string from valkey-forge 1.3.1, redis-forge 1.4.3, and rabbitmq-forge 1.5.1 onward.

- **Pipeline removed**

  We removed the dormant Concourse pipeline and its `ci/` tree, which included the script that generated release notes.

### Fixes

- **External director CA parameter**

  The external-bosh overlay took the broker's CA from `params.external_bosh.address` when an explicit value was given, and it now takes the CA from `params.external_bosh.cacert`.

- **Valkey forge availability zones**

  The `valkey-service` network's subnets inherited an environment-namespaced zone, while the forge plans deploy into the bare `z1` zone, so service deploys failed with a zone mismatch. The subnets now use `z1`, and the cluster plan no longer asks for `z2`, which the network never defined.

- **Numeric stemcell pins in forge plans**

  A pin such as `1.460` was normalized to `1.46` when the broker re-merged a plan, so BOSH could not find the stemcell. The new forge pins quote the version themselves, and that fixes the problem.

- **Fix-secrets divergence on every redeploy**

  The kit declared a `blacksmith_services_ca` certificate variable that nothing used, and it collided with the CA the post-deploy hook seeds into CredHub. We dropped the variable, so a redeploy no longer trips the fix-secrets guard.

- **Register no longer breaks the next CF deploy**

  The `register` addon used to copy `nats_client_cert` into the CF deployment's CredHub namespace, and Genesis refused the next CF deploy of a vault-managed environment because the manifest secret also existed in CredHub. The addon no longer writes it.

- **Cloud config check**

  The check for the cloud config's compilation block looked it up by name in a list, but the block is a single mapping with no name, so the check now reads the block directly.

- **Smaller corrections**

  We removed an empty duplicate `releases` key from the blacksmith release manifest, which merge tools that reject duplicate keys refused outright. We also fixed the retry warning for the CA sync, which passed its call path with a redundant argument.
