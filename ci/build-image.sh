#!/usr/bin/env bash
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_COMMIT_SHA:?}"
: "${CI_JOB_ID:?}"
: "${CI_PIPELINE_ID:?}"
: "${CI_COMMIT_BRANCH:?}"
: "${CI_DEFAULT_BRANCH:?}"
: "${CI_SERVER_PROTOCOL:?}"
: "${CI_REGISTRY_IMAGE:?}"
: "${PYTHON_BASE_IMAGE:?}"
: "${TRIVY_IMAGE:?}"
: "${SYFT_IMAGE:?}"
: "${PUBLISH_IMAGE:?}"

if [[ "$PUBLISH_IMAGE" != "true" && "$PUBLISH_IMAGE" != "false" ]]; then
  echo "PUBLISH_IMAGE must be true or false" >&2
  exit 1
fi

if [[ "$CI_SERVER_PROTOCOL" != "https" ]]; then
  echo "Refusing image work without GitLab HTTPS" >&2
  exit 1
fi

if [[ "$PUBLISH_IMAGE" == "true" && "$CI_COMMIT_BRANCH" != "$CI_DEFAULT_BRANCH" ]]; then
  echo "Refusing publish outside the default branch" >&2
  exit 1
fi

cd "$CI_PROJECT_DIR"
mkdir -p reports
image_tag="${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}-${CI_JOB_ID}"
docker_config=""
push_output=""
cleanup() {
  if [[ -n "$docker_config" ]]; then rm -rf -- "$docker_config"; fi
  if [[ -n "$push_output" ]]; then rm -f -- "$push_output"; fi
  docker image rm "$image_tag" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build --pull \
  --build-arg "PYTHON_BASE_IMAGE=$PYTHON_BASE_IMAGE" \
  --tag "$image_tag" apps/demo-app

docker pull "$TRIVY_IMAGE" >/dev/null
docker run --rm \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --env TRIVY_NO_PROGRESS=true \
  "$TRIVY_IMAGE" image --scanners vuln --severity HIGH,CRITICAL \
  --exit-code 1 --format json "$image_tag" > reports/image-scan.json

docker pull "$SYFT_IMAGE" >/dev/null
docker run --rm \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  "$SYFT_IMAGE" "$image_tag" -o cyclonedx-json > reports/sbom.cdx.json

image_id="$(docker image inspect --format '{{.Id}}' "$image_tag")"
scan_hash="$(sha256sum reports/image-scan.json | cut -d ' ' -f 1)"
sbom_hash="$(sha256sum reports/sbom.cdx.json | cut -d ' ' -f 1)"
printf 'commit=%s\npipeline_id=%s\njob_id=%s\nlocal_image_id=%s\nscan_sha256=%s\nsbom_sha256=%s\n' \
  "$CI_COMMIT_SHA" "$CI_PIPELINE_ID" "$CI_JOB_ID" "$image_id" \
  "$scan_hash" "$sbom_hash" > reports/image-evidence.txt

if [[ "$PUBLISH_IMAGE" == "false" ]]; then
  echo "Build, vulnerability scan and SBOM passed; publish skipped on feature branch"
  exit 0
fi

: "${CI_REGISTRY:?}"
: "${CI_REGISTRY_USER:?}"
: "${CI_REGISTRY_PASSWORD:?}"
docker_config="$(mktemp -d)"
push_output="$(mktemp)"
export DOCKER_CONFIG="$docker_config"

printf '%s' "$CI_REGISTRY_PASSWORD" | \
  docker login "$CI_REGISTRY" --username "$CI_REGISTRY_USER" --password-stdin
docker push "$image_tag" > "$push_output"
cat "$push_output"
digest="$(sed -n 's/.*digest: \(sha256:[0-9a-f]*\).*/\1/p' "$push_output" | tail -n 1)"
if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "Registry push did not return a valid image digest" >&2
  exit 1
fi
printf '%s@%s\n' "$CI_REGISTRY_IMAGE" "$digest" > reports/image-ref.txt
printf 'image_ref=%s@%s\n' "$CI_REGISTRY_IMAGE" "$digest" >> reports/image-evidence.txt
