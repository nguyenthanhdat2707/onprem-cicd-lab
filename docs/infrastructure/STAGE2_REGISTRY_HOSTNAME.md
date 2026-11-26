# Stage 2 registry hostname migration

Status (27/11/2026): hostname migration applied on GitLab, runner,
controller and worker. Runner-to-GitLab TLS and registry realm checks
passed. The local workstation now resolves the new hostname. Pipeline 59
confirmed Docker executor checkout and image publication, but its Cosign
container could not resolve the registry hostname. A local CI script fix is
prepared and awaits review before a protected-branch run.

## Docker runner checkout follow-up

- Pipeline 58 unit tests passed. Job 210 `secret-scan` failed during source
  checkout with `Could not resolve host: gitlab.lab.home.arpa`. The Docker
  executor container does not inherit the runner host's `/etc/hosts`
  mapping. Build and sign jobs were skipped; the Cosign fix remains
  unverified in CI.
- The runner service uses `/etc/gitlab-runner/config.toml` and is active.
  Its contents are protected from the unprivileged SSH user. GitLab Runner
  19.2.1 on this VM has no `lint` subcommand, while Python `tomllib` is
  available for syntax validation.
- Prepared `registry_hostname_runner_preflight.yml` to print only runner
  names, executors and `extra_hosts`, omitting registration tokens.
  `registry_hostname_runner.yml` requires one Docker runner, backs up the
  root-owned configuration with mode `0600`, adds
  `gitlab.lab.home.arpa:10.20.0.10` to its `extra_hosts` without dropping
  existing entries, validates TOML before replacement and checks the
  service. A separate rollback playbook restores the backup. Runner
  normally reloads config changes without a service restart.
- The operator reported that the runner preflight and apply playbooks ran.
  Their recaps were not shared. Pipeline 59 provides live evidence that the
  Docker executor now checks out the source successfully.

## Pipeline 59 follow-up: Cosign container DNS

- Pipeline 59 passed `unit-test`, Docker executor `secret-scan`, and
  `build-scan-sbom-publish`. The build reported zero high or critical image
  findings and pushed
  `gitlab.lab.home.arpa:5050/root/cicd-lab@sha256:7bdaa25d08d91ad082f03881f94cb861d4c4d1a6d46c4d18870e6487e606c041`.
- Sign job 218 failed before signing: Cosign's own `docker run` container
  queried `gitlab.lab.home.arpa` through `8.8.8.8` and received `no such
  host`. Runner `extra_hosts` affects Docker executor job containers, not
  containers launched by a shell job's script.
- The local `ci/sign-image.sh` patch resolves `$CI_REGISTRY` on the runner
  and passes that hostname/IP pair to each Cosign container with
  `docker run --add-host`. It also sets a writable `HOME=/tmp` to avoid the
  observed `mkdir /.sigstore: permission denied` TUF cache warning. The
  mapping is limited to the container and does not change system DNS.
- This patch has not been committed or run in a protected-branch pipeline.
  After review, test it on `main` and require signing plus attestation
  verification artifacts before promoting the digest in GitOps.

```sh
cd /home/tdat/Documents/Learn/Uni/DACN2-Final/ansible
ANSIBLE_LOCAL_TEMP=/tmp/ansible-stage2 \
ANSIBLE_SSH_ARGS='-F /dev/null -o ControlMaster=auto -o ControlPersist=60s' \
ansible-playbook playbooks/registry_hostname_runner_preflight.yml --ask-become-pass
```

## Applied state and verification

- The successful GitLab run retained backup
  `/etc/gitlab/stage2-registry-hostname-20261126T163530Z` and ended with
  `ok=43`, `changed=16`, `failed=0`. The GitLab HTTPS sign-in and registry
  bearer-realm assertions passed after `gitlab-ctl reconfigure`.
- From the runner, `gitlab.lab.home.arpa` resolves to `10.20.0.10`; the
  GitLab sign-in endpoint returns HTTP 200 over validated TLS. Registry
  `/v2/` returns HTTP 401 and
  `Bearer realm="https://gitlab.lab.home.arpa/jwt/auth"`.
- The certificate actually served by GitLab has
  `DNS:gitlab.lab.home.arpa` and `IP Address:10.20.0.10`, SHA-256
  fingerprint
  `65:54:CB:55:A5:E0:74:74:D4:AE:E0:35:1E:BB:1A:0D:6C:58:78:29:2C:3C:EC:E4:D7:0E:64:93:DA:04:5E:AA`.
- The local Ansible workstation initially had no hostname resolution. After
  the operator added a hosts entry, `getent ahostsv4` returned `10.20.0.10`.
  A `curl --resolve` check had already returned HTTP 200 over trusted TLS.

## Incident and recovery history

- The first GitLab apply attempt created backup
  `/etc/gitlab/stage2-registry-hostname-20261126T161153Z`, then stopped at
  `Sign the server CSR with the existing local lab CA`. Its temporary
  server key and CSR were removed. No certificate was installed and
  `gitlab-ctl reconfigure` did not run.
- Read-only local diagnosis showed the existing `lab-ca.key` requires a
  passphrase. The revised playbook prompts privately only when it needs
  to issue a certificate and passes the input to OpenSSL on stdin using
  `-passin fd:0`. The playbook does not put the passphrase in command
  arguments or intentionally write it to a persistent file; `no_log`
  suppresses task results. Ansible holds the input in memory during the
  task. The play variable is cleared in the cleanup block.
- The second attempt created backup
  `/etc/gitlab/stage2-registry-hostname-20261126T162656Z`, issued and
  installed a certificate, then wrote invalid `gitlab.rb`: the old Jinja
  expression emitted literal `\n` instead of line breaks. GitLab's
  `reconfigure` failed Ruby syntax checking before updating generated
  resources. The operator ran the rollback playbook using this backup;
  it restored configuration/certificate/key, reconfigured GitLab and
  verified the original HTTPS IP endpoint (`failed=0`).
- The corrected playbook renders a separate Jinja template with real line
  breaks. It tests a candidate with GitLab's embedded `ruby -c` before
  active certificate/configuration changes and uses Ansible's `validate`
  again before atomically replacing `gitlab.rb`. If syntax checking fails,
  the temporary candidate is removed and the active files remain intact.
  A retry starts from the first task and creates another backup. Keep
  both previous backups until the migration is verified.

## Evidence and decision

- Pipeline 57 published image digest
  `sha256:fcd1ce2f3fbcb26a38672d123bccd3044c810f843c1d1a71b96799e8b8527ddb`,
  but sign job 206 failed before signing.
- Before migration, registry `GET /v2/` advertised
  `Bearer realm="https://10.20.0.10/jwt/auth"`.
- The local copy `/home/tdat/homelab-pki/gitlab.crt` has only IP SAN
  `10.20.0.10` (SHA-256 fingerprint
  `71:76:AD:23:3A:2E:04:22:1B:7C:1A:AA:7C:FF:48:06:C4:E0:CC:22:FF:89:94:19:FE:90:06:05:CB:40:89:59`).
  The certificate installed on the GitLab VM is rechecked by the apply
  playbook before it decides whether to issue a replacement.
- The existing `Homelab Root CA` certificate has SHA-256 fingerprint
  `3B:80:AE:BC:7C:AB:13:49:A2:A2:84:42:EF:BE:62:FD:17:AF:A8:76:DC:D5:F1:AD:79:31:61:D4:11:57:81:C6`.
  The CA private key exists locally at `/home/tdat/homelab-pki/lab-ca.key`
  with mode `0600`; it is not copied to a VM or committed to Git.
- The GitLab VM has certificate/key paths `/etc/gitlab/ssl/gitlab.crt` and
  `/etc/gitlab/ssl/gitlab.key`. Its `gitlab.rb` has three active
  `external_url` declarations for the IP endpoint plus one
  `registry_external_url` for the IP and port 5050. The apply playbook
  consolidates these into one active declaration of each URL.
- The operator preflight reported 24 GB free on GitLab. It reported no
  `/etc/hosts` mapping on the controller; the apply playbooks check each
  host's actual resolution before adding an entry.
- Cosign rejects a bearer realm whose host is a literal private IP.
  GitLab's own documentation requires a resolvable hostname for image
  signing. The earlier IP-only TLS choice worked for Docker push/pull but
  does not meet this Stage 2 constraint.

Use `gitlab.lab.home.arpa` for both GitLab and registry port 5050. If the
installed certificate already has both the DNS and IP SAN, keep it. If it
does not, issue a new server certificate with both SANs using the existing
lab CA. Prefer a lab DNS record; the prepared client playbook adds a hosts
entry only when the name does not already resolve. A DNS service and
Kubernetes DNS integration can replace those host mappings later.

## Privileged preflight for the operator

All four VM accounts require a sudo password, but this read-only playbook
uses sudo only on the GitLab VM. Do not send that password in chat or save
it in Git. From the source repository's `ansible/` directory, run:

```sh
ANSIBLE_LOCAL_TEMP=/tmp/ansible-stage2 \
ANSIBLE_SSH_ARGS='-F /dev/null -o ControlMaster=auto -o ControlPersist=60s' \
ansible-playbook playbooks/registry_hostname_preflight.yml --ask-become-pass
```

This playbook reads hostname resolution and only GitLab URL/certificate-path
settings, candidate certificate filenames and disk space. It does not print
private key contents or the full `gitlab.rb`. Share the output after
checking that no local path should be kept private. It does not back up or
change configuration; those actions belong to the later apply playbook.

## Change design

1. `registry_hostname_clients.yml` prepares runner, controller and worker:
   resolves the new hostname to `10.20.0.10` when DNS is absent, installs
   the existing CA in OS trust, and adds Docker registry CA trust on the
   runner. Run each host separately if their sudo passwords differ. This
   precedes the GitLab URL switch so the runner can resolve its new
   `$CI_REGISTRY` endpoint immediately.
2. `registry_hostname_gitlab.yml` checks the *installed* certificate SAN
   and verifies the CA certificate on GitLab matches the local CA. It
   creates a private backup directory under `/etc/gitlab/` containing
   `gitlab.rb`, server certificate and server key. Only if the installed
   certificate lacks either SAN or fails validation against the current
   CA does it create a new server key/CSR in a
   temporary local directory, sign with the existing CA key, validate the
   certificate and copy the new certificate/key to GitLab. The temporary
   local private key and CSR are removed even if the signing step fails.
3. Before changing files, the GitLab playbook stops if it finds an explicit
   `registry['token_realm']` or `gitlab_rails['registry_host']` override;
   these settings require separate review. Otherwise, it adds a hosts
   entry if needed, removes all active
   `external_url` and `registry_external_url` declarations in a rendered
   template, then writes exactly one of each with the hostname. Other
   GitLab configuration lines remain. Ruby syntax is checked before any
   active file changes and again at installation. It runs
   `gitlab-ctl reconfigure` once and checks the GitLab sign-in page plus
   the registry's bearer realm over CA-validated HTTPS.
4. `registry_hostname_rollback.yml` accepts only a recorded backup path,
   restores the three backed-up GitLab files, reconfigures GitLab and
   checks the original IP endpoint. Client hosts entries and CA trust can
   remain during rollback; they do not change the old IP URL. Do not
   delete registry image data or signing artifacts.

All mutation playbooks require an explicit
`-e confirm_registry_hostname_change=true` or
`-e confirm_registry_hostname_rollback=true`. The client playbook has
already run successfully on the three client VMs. The original GitLab
state was restored after the failed second attempt; the corrected third
attempt applied the hostname migration successfully.

The URL switch changes URLs GitLab advertises to users, API clients,
webhooks, Git remotes over HTTPS and CI variables such as `$CI_REGISTRY`.
The retained IP SAN allows existing IP-based TLS clients to continue during
migration, but application redirects and generated links will use the new
hostname. Plan a maintenance window and update clients that require the
new URL.

## Preparation checks

The playbooks passed Ansible syntax checking and `ansible-lint`. A local
Jinja render using synthetic GitLab configuration confirmed the new
template emits real line breaks, URL normalization is repeatable and
unrelated settings remain. Synthetic SAN cases confirmed that
the certificate decision distinguishes the exact DNS/IP names and checks
the CA validation result. Ansible's local runtime smoke test could not
start its RPC server inside the Codex sandbox. The operator's successful
client playbook runs provide the live verification for those hosts. A
separate local test with a synthetic passphrase-protected CA confirmed
that OpenSSL accepts `-passin fd:0`, signs a CSR and produces a certificate
with both required SANs. The production CA key was not used in this test.

## Completed operator sequence

The three client playbook runs and the final GitLab run have completed
successfully. The command used for the final GitLab run was:

```sh
ANSIBLE_LOCAL_TEMP=/tmp/ansible-stage2 \
ANSIBLE_SSH_ARGS='-F /dev/null -o ControlMaster=auto -o ControlPersist=60s' \
ansible-playbook playbooks/registry_hostname_gitlab.yml \
  --ask-become-pass -e confirm_registry_hostname_change=true
```

The first prompt asked for the GitLab sudo password; a later hidden
prompt asked for the local lab CA key passphrase. Neither secret was
passed on the command line or in chat.

Stop on any failed or unexpected result. Record the backup path printed
before `gitlab-ctl reconfigure`. If GitLab must be restored, review that
backup path and run:

```sh
ansible-playbook playbooks/registry_hostname_rollback.yml --ask-become-pass \
  -e confirm_registry_hostname_rollback=true \
  -e backup_dir=/etc/gitlab/stage2-registry-hostname-YYYYMMDDTHHMMSSZ
```

Next, review the Cosign container hostname patch and run a fresh `main`
pipeline after it is integrated. After the signing job passes, check Docker
login/push/pull on the runner and a Kubernetes pull from the new registry
hostname. The client playbook does not change containerd registry
configuration; verify its trust path before switching GitOps image
references. The local CI patch sets a writable Cosign HOME; verify that its
TUF cache warning is gone. Only then update GitOps image references and the
namespace-specific image pull Secret, and sync Argo CD.

References:
[GitLab signing requirements](https://docs.gitlab.com/ci/yaml/signing_self_hosted/),
[GitLab registry administration](https://docs.gitlab.com/administration/packages/container_registry/),
[Ansible template validation](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/template_module.html),
[GitLab Runner Docker configuration](https://docs.gitlab.com/runner/configuration/advanced-configuration/).
