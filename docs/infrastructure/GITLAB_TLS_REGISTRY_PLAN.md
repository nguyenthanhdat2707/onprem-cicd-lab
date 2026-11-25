# GitLab HTTPS, registry and runner gate

Status: proposed infrastructure change, 25/11/2026. No configuration in this
plan has been applied. Live findings are in `STAGE0_STATUS_2026-11-25.md`.

## Problem and intended outcome

GitLab CE 19.2.1 served HTTP on `10.20.0.10:80` at the last live check; port
443 and the expected registry port 5050 were closed. The source and GitOps
projects now exist, and Git over SSH works. Stage 1 build/publish still needs
trusted TLS and a reachable registry.

For the existing private subnet, the smallest workable endpoint design is
`https://10.20.0.10` for GitLab and `https://10.20.0.10:5050` for the registry,
using a private lab CA and a server certificate with IP SAN `10.20.0.10`.
This avoids depending on a DNS service not yet verified. A stable lab FQDN
with DNS and a matching certificate is preferable if one already exists.
The CA must be trusted by the Ansible machine, runner, controller and worker;
otherwise HTTPS and image pulls will still fail.

## Read-only prechecks before a change

1. With authorized administrator access, inspect the active `external_url`,
   registry settings, nginx settings, certificate paths and GitLab data path.
   Back up current configuration and identify the restore command. Do not
   print secret keys, tokens or the full `gitlab.rb` into logs.
2. Confirm free space in GitLab's data filesystem and Proxmox `local-lvm`.
   Estimate image, SBOM, signature and cache growth plus a retention policy.
3. Inspect runner registration, executor and project scope. The service runs
   jobs as `gitlab-runner`, a member of the Docker group; treat this as broad
   host access when choosing trusted branches and job permissions.
4. Confirm the host/VM firewall path to 443 and 5050, and that the private CA
   can be distributed to each client without storing its private key in Git.

## Proposed change order and verification

1. Create the CA and IP-SAN server certificate in a protected location;
   distribute **only** the CA certificate to clients. Keep private keys off
   the source and GitOps repositories.
2. Configure GitLab's HTTPS `external_url`, manual certificate and disabled
   Let's Encrypt renewal; configure `registry_external_url` on the same IP
   with port 5050. Reconfigure GitLab once during a maintenance window.
3. Verify GitLab UI/API over HTTPS with certificate validation from the
   Ansible machine and runner. Confirm HTTP redirects to HTTPS as intended.
4. Verify `GET /v2/` on registry endpoint returns the expected authentication
   challenge over validated TLS, then authenticate and push/pull a small
   disposable image using a scoped credential.
5. Configure registry CA trust for containerd on both Kubernetes nodes;
   pull the test image from the worker and check disk consumption. Remove the
   disposable image according to its exact digest after recording evidence.
6. Run one small CI job on the verified runner. Record its executor, user,
   access to Docker and filesystem, and whether untagged jobs are accepted.
   Choose the builder only after this result. Do not enable privileged
   Docker-in-Docker by default.
7. Push this workspace root to the existing **source** GitLab project; keep
   later GitOps Helm/manifests in `cicd-gitops-lab`. The root `.gitlab-ci.yml`
   first runs app unit tests, then scan/build/SBOM/publish jobs are added one
   verified gate at a time.

Stop if certificate validation fails, registry storage is unclear, the
runner's authority is broader than intended, or cluster health degrades.
Restore the backed-up GitLab configuration and reconfigure only after
diagnosing the failed step; do not delete registry data as a rollback shortcut.

## References

- [GitLab Linux package SSL configuration](https://docs.gitlab.com/omnibus/settings/ssl/)
- [GitLab container registry administration](https://docs.gitlab.com/administration/packages/container_registry/)
- [GitLab Runner security](https://docs.gitlab.com/runner/security/)
- [GitLab Shell executor](https://docs.gitlab.com/runner/executors/shell/)
