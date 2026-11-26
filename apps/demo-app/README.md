# Sample app for the security lab

One image runs three roles selected by `ROLE=frontend|api|decoy`. The frontend
calls `API_URL` on `/`; `/healthz` reports the local process state. All responses
are fixed JSON, so scenario probes can compare identical inputs before and
after security controls.

Run tests without installing dependencies:

```bash
cd apps/demo-app
python3 -m unittest -v
```

Run an API locally, then a frontend in another terminal:

```bash
ROLE=api PORT=8081 python3 apps/demo-app/app.py
ROLE=frontend PORT=8080 API_URL=http://127.0.0.1:8081/message python3 apps/demo-app/app.py
curl -f http://127.0.0.1:8080/
```

The Dockerfile requires an explicit `PYTHON_BASE_IMAGE` build argument. CI uses
the digest-pinned Python 3.12 Alpine 3.24 image in `ci/image.yml` and installs
the patched `krb5-libs` package. Local Compose builds must use an Alpine 3.24
base digest as well. No image is deployed by this local preparation step.

For a local three-service run, set `PYTHON_BASE_IMAGE` to an approved image
reference and run `docker compose up --build` from this directory. The frontend
is available at `http://127.0.0.1:8080/` and the decoy at
`http://127.0.0.1:8082/`. Compose leaves the API on its internal network.
The GitLab CI entrypoint is at the workspace root; this app directory contains
only application, test, container and local development files.
