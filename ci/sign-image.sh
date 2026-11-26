#!/usr/bin/env bash
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_COMMIT_BRANCH:?}"
: "${CI_DEFAULT_BRANCH:?}"
: "${CI_COMMIT_REF_PROTECTED:?}"
: "${CI_SERVER_PROTOCOL:?}"
: "${CI_REGISTRY:?}"
: "${CI_REGISTRY_USER:?}"
: "${CI_REGISTRY_PASSWORD:?}"
: "${CI_REGISTRY_IMAGE:?}"
: "${COSIGN_IMAGE:?}"
: "${COSIGN_PRIVATE_KEY:?Set a protected File CI variable}"
: "${COSIGN_PUBLIC_KEY:?Set a protected File CI variable}"
: "${COSIGN_PASSWORD:?Set a protected masked CI variable}"

if [[ "$CI_SERVER_PROTOCOL" != "https" || "$CI_COMMIT_BRANCH" != "$CI_DEFAULT_BRANCH" || "$CI_COMMIT_REF_PROTECTED" != "true" ]]; then
  echo "Refusing to sign outside the protected default branch over HTTPS" >&2
  exit 1
fi

cd "$CI_PROJECT_DIR"
test -s reports/image-ref.txt
test -s reports/sbom.cdx.json
test -s "$COSIGN_PRIVATE_KEY"
test -s "$COSIGN_PUBLIC_KEY"
image_ref="$(cat reports/image-ref.txt)"
if [[ ! "$image_ref" =~ ^[^[:space:]]+@sha256:[0-9a-f]{64}$ || "$image_ref" != "$CI_REGISTRY_IMAGE"@sha256:* ]]; then
  echo "Image artifact is not a digest in this project's registry" >&2
  exit 1
fi

docker_config="$(mktemp -d)"
chmod 700 "$docker_config"
cleanup() { rm -rf -- "$docker_config"; }
trap cleanup EXIT
export DOCKER_CONFIG="$docker_config"
printf '%s' "$CI_REGISTRY_PASSWORD" | docker login "$CI_REGISTRY" --username "$CI_REGISTRY_USER" --password-stdin >/dev/null
docker pull "$COSIGN_IMAGE" >/dev/null

cosign_run() {
  docker run --rm --user "$(id -u):$(id -g)" \
    --env COSIGN_PASSWORD --env DOCKER_CONFIG=/run/docker \
    --env SSL_CERT_FILE=/run/ca-bundle.crt \
    --volume "$docker_config:/run/docker:ro" \
    --volume "$COSIGN_PRIVATE_KEY:/run/secrets/cosign.key:ro" \
    --volume "$COSIGN_PUBLIC_KEY:/run/secrets/cosign.pub:ro" \
    --volume "$CI_PROJECT_DIR/reports:/reports" \
    --volume /etc/ssl/certs/ca-certificates.crt:/run/ca-bundle.crt:ro \
    "$COSIGN_IMAGE" "$@"
}

cosign_run sign --yes --tlog-upload=false --key /run/secrets/cosign.key "$image_ref"
cosign_run attest --yes --key /run/secrets/cosign.key \
  --type cyclonedx --predicate /reports/sbom.cdx.json "$image_ref"
cosign_run verify --insecure-ignore-tlog --key /run/secrets/cosign.pub \
  "$image_ref" > reports/signature-verify.json
cosign_run verify-attestation --insecure-ignore-tlog \
  --key /run/secrets/cosign.pub --type cyclonedx \
  "$image_ref" > reports/attestation-verify.json
test -s reports/signature-verify.json
test -s reports/attestation-verify.json
printf 'image_ref=%s\nsbom_sha256=%s\ncosign_image=%s\nsignature=verified\nattestation=verified\n' \
  "$image_ref" "$(sha256sum reports/sbom.cdx.json | cut -d ' ' -f 1)" \
  "$COSIGN_IMAGE" > reports/signing-evidence.txt
echo "Signature and CycloneDX attestation verified for $image_ref"
