# Stage 0 live status — 25/11/2026

Scope: read-only checks from the Ansible machine and SSH into Proxmox and the
four project VMs. No VM, GitLab, registry or Kubernetes configuration changed.
The demo app and local plan are separate workspace changes.

## Confirmed at 18:10–18:13 ICT

- Proxmox `pve` is reachable. VM 100 (worker), 102 (runner), 103 (GitLab),
  104 (controller) and 101 are running. VM 105 is stopped.
- Routes to `10.20.0.10`, `.11`, `.12`, `.15` use `192.168.101.81`.
- Controller `ens19` has `10.20.0.15/24`; worker `ens19` has
  `10.20.0.12/24`. Both kubelet and containerd services are active.
- API `/readyz` returns `ok`. Both Kubernetes v1.36.6 nodes are `Ready`.
  Cilium, Cilium operator, CoreDNS and control-plane pods are `Running`.
- The latest etcd/API server pod restart was during this boot (12 total for
  each). Earlier restart causes remain unknown.
- Guest root free space: controller 5.09 GiB, worker 10.28 GiB, runner
  8.93 GiB, GitLab 24.15 GiB. These are point-in-time values.
- Proxmox `MemAvailable` was 16.88 GiB at 18:12:48; `local-lvm` had
  68.93 GiB available. VM memory can still rise under build/scan load.
- GitLab service is active. HTTP on `10.20.0.10:80` redirects to the login
  page. HTTPS on port 443 does not accept connections; nginx listens on 80.
  The unauthenticated version API returns 401, which does not prove an
  authenticated API request works.
- The GitLab runner service and Docker daemon are active. The SSH user
  `runner` cannot use `/var/run/docker.sock`. The service is configured to
  execute jobs as `gitlab-runner`, which belongs to the `docker` group.
  This gives the job account broad access to the host Docker daemon if the
  executor runs jobs under that account. The configured executor and an actual
  job's permissions remain unverified; the runner config is root-only.
- The expected GitLab registry endpoint on port 5050 does not accept
  connections. The actual registry configuration has not been confirmed.

## Gate assessment

Cluster and route checks pass at this point in time. Stage 0 is **incomplete**:
GitLab/registry TLS, registry availability, runner registration/job execution,
node-to-registry pull, prior control-plane restart cause and a workload budget
have not been verified. Stage 1 build/publish/deploy must wait for these gates.

## Next implementation decisions

1. Choose a stable GitLab and registry name or IP certificate SAN, provide
   trusted HTTPS, then verify trust from runner and Kubernetes nodes.
2. Enable and verify the GitLab container registry. Record its endpoint,
   available storage, retention policy and authentication method.
3. Inspect runner registration and executor without exposing registration
   tokens. Run a small job before choosing a builder. Treat Docker-group
   access of `gitlab-runner` as a host privilege boundary to review; the
   SSH account's Docker permission does not describe the job account.
4. Measure host/guest disk and RAM during one build and scan. Define limits
   before adding further controllers or observability components.
5. Create the GitLab source project from this workspace root. Its app lives
   under `apps/demo-app/` and its CI entrypoint is `.gitlab-ci.yml`. Then add
   scan, build, SBOM and publish jobs using the verified builder and registry.
   Keep the GitOps repository separate.

Do not treat the local unit-test CI job as a completed Stage 1 pipeline.
