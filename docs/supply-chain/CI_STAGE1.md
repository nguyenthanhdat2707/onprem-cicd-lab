# Stage 1 CI status

The source pipeline is configured to run the demo app unit test on runner tag
`network-lab`, then a Trivy 0.76.2 secret scan on runner tag `homelab`.
The Docker and shell runner diagnostics remain optional manual jobs.
The Trivy job has not yet been observed running on GitLab.
While GitLab advertises HTTP, the scan is optional/manual. Once
`CI_SERVER_PROTOCOL` is `https`, it runs automatically and fails the pipeline
on findings. This gate protects future runs after trusted TLS is configured;
it does not retroactively secure the existing HTTP runner connection.

The secret job writes the raw Trivy JSON to a temporary file and deletes it
before exit. Only `reports/secret-summary.json` is retained as a seven-day
artifact; it contains scanner version, commit SHA, outcome and finding count, without
matched values. A finding fails the job. `ci/trivy-secret.yaml` adds a
deterministic lab marker rule for S01 while retaining Trivy's built-in rules.
The marker format is `LAB_FAKE_SECRET_` followed by 16 uppercase letters or
digits. Use only synthetic values in a demo branch; do not commit real keys.

This is **not** the full Stage 1 pipeline. Image build, image vulnerability
scan, CycloneDX SBOM and registry publish remain pending. At the last live
check GitLab served HTTP on port 80, while HTTPS and the expected registry
port were unavailable. The local machine's route to `10.20.0.0/24` also
reverted to the wrong next hop; access through Proxmox jump host still worked.

Next gates: verify the Trivy job runs on the intended Docker runner, then
configure trusted TLS/registry and measure resource use before adding build,
SBOM and publish jobs. Do not pass registry credentials through HTTP or put
kubeconfig into the source pipeline.
