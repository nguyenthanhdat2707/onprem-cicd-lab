# Stage 1 local implementation plan

Status: local preparation in progress, 25/11/2026. Live GitLab, registry,
runner and cluster checks must pass before deployment.
The current findings and gate status are in
`../infrastructure/STAGE0_STATUS_2026-11-25.md`.

## Shape of the demo

```text
GitLab source repo ── CI test/scan/build/SBOM ── GitLab registry
       │                                          │
       └── evidence: commit, pipeline, reports ───┘

frontend (demo-app) ──HTTP──> api (demo-app)
                              decoy (demo-decoy; S05 probe target)
```

`apps/demo-app/` contains one dependency-free Python service with three roles.
One image simplifies attribution: every role can be traced to the same commit
and image digest. The frontend `/` request proves the allowed frontend-to-API
path; `/healthz` only proves its own process is alive. The decoy is a separate
service for the S05 reachability probe. No production data or credentials are
part of the app.

## Sequence and gates

1. Confirm the four VMs and cluster are running, including stable controller
   IP/route, available memory/disk, and no unexplained control-plane restarts.
2. Confirm GitLab UI/API, TLS certificate, registry endpoint, runner
   registration, executor and a small non-privileged job. Record exact versions
   and available storage before choosing the image builder.
3. Create a GitLab source project and configure a runner with the least
   required permissions. Keep cluster credentials out of CI.
4. Add CI jobs for unit tests, secret/source scan, image build, image scan,
   CycloneDX SBOM and publish. Pin tool and base-image versions/digests, and
   record commit SHA, pipeline ID, image digest and report artifacts.
5. Check node-to-registry pull over trusted TLS. Deploy only by digest after
   Stage 1 gates pass; test frontend `/` and both `/healthz` endpoints.

The root `.gitlab-ci.yml` includes `ci/demo-app.yml`, currently a unit-test
job only. Builder, registry URL and Kubernetes manifests depend on live
runner/registry checks. Do not assume Docker-in-Docker or privileged mode.
GitOps, signing and admission belong to later stages in `PROJECT_SPEC.md`.
Repository boundaries are in `REPOSITORY_ARCHITECTURE.md`.

## Stage 1 acceptance

- Local unit tests pass; a frontend request gets the API's fixed response.
- A real GitLab pipeline links a commit to test/scan results, an image digest
  and a CycloneDX SBOM. A fake secret test fails the intended CI gate.
- Nodes pull the published digest over trusted TLS, and deployed frontend,
  API and decoy respond as expected without breaking cluster health.
- Build cache, registry growth and node disk remain within measured budget.
