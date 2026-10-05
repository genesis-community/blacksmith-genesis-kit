# Changelog

## Unreleased

CredHub cleanup of deprovisioned service instances now runs by default whenever the director is external, which means the environment uses `external-bosh` or `ocfp`. The internal director has no CredHub, so the kit leaves cleanup off for it. The hourly sweep for older orphaned variables starts in `dry-run` mode, so the broker logs what it would delete and deletes nothing until we set `credhub_cleanup.sweep` to `delete`.

The new `skip-credhub-cleanup` feature turns cleanup off for an external director.

The `credhub-cleanup` feature name is deprecated and does nothing now. Existing env files that list it still validate, and we can remove the name at our convenience.

The client ID, secret, CredHub URL, CA, and director name now come from the director's exodus record, which the BOSH kit publishes when the director uses its `blacksmith-integration` feature. If any of those keys is missing, the deploy warns and names each missing key, cleanup stays unwired, and the broker deletes nothing from CredHub. The fix is to redeploy the director with a BOSH kit release that publishes them.

The kit no longer generates the `users/credhub-cleanup` secret in vault, so `genesis add-secrets` does not create it, and the manual no longer has the hand procedure for creating the UAA client.

The post-deploy check of the cleanup client now authenticates with the secret from the director's exodus record. If that check fails, the warning tells us to redeploy the director with the current BOSH kit release.
