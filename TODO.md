TODO:

[ ] provide an +internal-bosh internal feature flag to only include the
    bosh and related releases (currently gets installed even on
    external-bosh feature flag)

[ ] separate out all the releases from the forges into the releases
    subdirectory so each has its own <release-name>.yml file, then include
    that file into the manifests list in hooks/blueprint script

[ ] add the releases to the upstream bosh releases section of the
    ci/settings.yml file so they can be updated via the pipeline.

[ ] in check_sha script, download file separately before calculating sha1sum
    and check that it isn't an error

[ ] get head of resource url in check_sha script and get size and modified
    date, check that file exists, and that the downloaded file matches the
    size.

[ ] Utilize a s3 or redis datastore to cache urls with their calculated sha,
    size and modified date so we don't have to download the file every time.



