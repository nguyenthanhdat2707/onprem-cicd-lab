# Stage 2: signed digest and reviewed GitOps promotion

## Current boundary

The Stage 1 `main` pipeline publishes an image by digest and produces a
CycloneDX JSON SBOM. The cluster has no Argo CD installation yet. The GitOps
repository is `root/cicd-gitops-lab` and its chart/Application manifests are
prepared on a separate feature branch.

## Signing flow

The `sign-image-and-sbom` job runs only on a protected default branch over
HTTPS, after `build-scan-sbom-publish` succeeds. It reads that job's
`reports/image-ref.txt` and SBOM artifact, refuses a tag or an image outside
the current project, signs the digest, attaches a CycloneDX attestation, and
verifies both with the public key. The job has registry access, but no
Kubernetes credentials or GitOps write access.

Create one lab Cosign key pair. In the source project GitLab CI/CD variables,
configure:

| Variable | Type | Protection | Value |
| --- | --- | --- | --- |
| `COSIGN_PRIVATE_KEY` | File | Protected | Contents of the encrypted Cosign private key |
| `COSIGN_PUBLIC_KEY` | File | Protected | Matching public key PEM |
| `COSIGN_PASSWORD` | Variable | Protected, masked | Private-key passphrase |

Keep the private key and password out of both repositories and job logs. Use a
dedicated lab key, record its public-key fingerprint, and retain a secure
offline backup. For this isolated lab, the signing command disables public
transparency-log upload with `ci/signing-config.json`; verification explicitly checks the key signature
without a transparency-log proof. This verifies the key-holder but does not
provide public timestamp or append-only audit evidence.

The runner already trusts the GitLab registry TLS certificate through its
system CA bundle, which the Cosign container mounts read-only. The pinned
Cosign container tag is `v3.1.1`. After the first protected-branch pipeline,
check `reports/signing-evidence.txt`, the signature and attestation verification
artifacts, and independently verify the digest with the same public key.
Test a different or unsigned digest and require verification to fail.

## GitOps promotion

The GitOps repo contains `charts/demo-app/`, `environments/lab/` and
`argocd/`. Its frontend and API Applications pin the same digest, have no
automated sync policy, and use the existing `demo-app/gitlab-registry` pull
Secret. The current pin is the unsigned Stage 1 digest and must not be synced
until it has been signed, or replaced by a signed digest from a later pipeline.

Bootstrap Argo CD v3.6.3 with reviewed, pinned CRDs and the
`namespace-install.yaml` manifest in `argocd`. The namespace-scoped manifest
does not include CRDs. Give its controller a RoleBinding only in `demo-app`; use the
AppProject to restrict source repository, destination namespace, and resource
kinds. Configure a read-only GitLab deploy key and verified SSH host key as
Argo CD repository credentials, outside Git. Review and merge the GitOps
digest change, then manually sync and check both Applications are
`Synced`/`Healthy` and frontend returns HTTP 200.

Do not treat GitOps sync as an admission signature check. Enforcing the public
key at admission is Stage 3. A successful Stage 2 sync proves deployment of
the reviewed digest, not rejection of an unsigned Pod by Kubernetes.
