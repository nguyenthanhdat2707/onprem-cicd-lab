# Stage 1 CI status

The source pipeline is configured to run the demo app unit test on runner tag
`network-lab`, then a Trivy 0.76.2 secret scan on runner tag `homelab`.
The Docker and shell runner diagnostics remain optional manual jobs.
Runner logs confirmed that pipeline 40 ran jobs 134 and 137 successfully after
HTTPS and runner access were enabled. The image job has not yet been observed.
With `CI_SERVER_PROTOCOL=https`, the secret scan runs automatically and fails
the pipeline on findings.

The secret job writes the raw Trivy JSON to a temporary file and deletes it
before exit. Only `reports/secret-summary.json` is retained as a seven-day
artifact; it contains scanner version, commit SHA, outcome and finding count, without
matched values. A finding fails the job. `ci/trivy-secret.yaml` adds a
deterministic lab marker rule for S01 while retaining Trivy's built-in rules.
The marker format is `LAB_FAKE_SECRET_` followed by 16 uppercase letters or
digits. Use only synthetic values in a demo branch; do not commit real keys.

The image job builds the demo app from a digest-pinned Python base image,
blocks on HIGH/CRITICAL image vulnerabilities with Trivy 0.76.2, and writes a
CycloneDX JSON SBOM with Syft v1.57.2. It uses the `network-lab` shell runner
and its Docker daemon, avoiding a second privileged Docker daemon. On feature
branches it runs automatically but stops before registry login or push. On the
default branch it runs automatically after the test and secret-scan stages, then pushes
a commit-SHA/job-ID tag to the project registry. The pushed digest is saved
as `reports/image-ref.txt`. `reports/image-evidence.txt` links that digest to
the commit, pipeline, local image ID, scan report hash and SBOM hash. Reports
expire after seven days. The script checks
HTTPS and the default branch again before accepting publish mode, even if CI
variables are overridden. The job removes its local commit-tagged image on exit
to limit runner disk use; Docker's shared build cache is left in place.

At the 2026-11-26 read-only check, `https://10.20.0.10/` returned HTTP 302
with valid TLS verification, and `https://10.20.0.10:5050/v2/` returned HTTP
401 with valid TLS verification. This confirms the registry endpoint is live;
Docker login, build, scan, SBOM generation and push still require a real runner
job for end-to-end confirmation. Do not put kubeconfig into the source pipeline.
