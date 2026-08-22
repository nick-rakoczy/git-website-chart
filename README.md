# Static site Helm chart

This chart builds a private Git repository with Argo Workflows and serves the
published static files with nginx. Build tasks may use different images and run
in parallel. A successful workflow assembles their outputs on a persistent
volume and atomically switches nginx to the new release.

Repositories without a build step are also supported: leave `build` empty and
the workflow publishes the checked-out repository contents directly.

## Prerequisites

- Kubernetes with a filesystem-backed `ReadWriteOnce` storage class
- Argo Workflows watching the release namespace
- Argo Events and an EventBus when `events.enabled` is true
- A node on which nginx and every Workflow pod can be scheduled together
- A GitHub App with read-only Contents access, or a read-only SSH deploy key
- A Kubernetes Secret containing the selected authentication credentials

`ReadWriteOnce` permits the claim to be mounted by multiple pods on one node.
Set the same node selector for nginx and the Workflow. By default,
`workflow.nodeSelector` inherits the chart's top-level `nodeSelector`.

## Git credentials

The chart can consume an existing Secret or create a 1Password
`OnePasswordItem`.

### GitHub App authentication

GitHub App authentication is recommended when multiple sites share access to
private repositories. Install the App on the required repositories with
read-only Contents access. The 1Password item must contain fields named
`application_id`, `installation_id`, and `private_key`; the resulting Secret
must look like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: static-sites-git
type: Opaque
stringData:
  application_id: "123456"
  installation_id: "12345678"
  private_key: |-
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
```

Configure the chart with an HTTPS repository URL:

```yaml
site:
  repository: https://github.com/your-org/example.com.git

gitCredentials:
  authentication: githubApp
  secretName: static-sites-git
  onePassword:
    enabled: true
    itemPath: vaults/Kubernetes/items/static-sites-git
```

Each build pod runs `git-sync` once before the build. It uses the App private
key to mint a short-lived installation token, just as the previous sidecar did.
To use an existing Secret, leave `onePassword.enabled: false` and set
`gitCredentials.secretName`.

Override the Secret field names when necessary:

```yaml
gitCredentials:
  githubApp:
    applicationIdKey: application_id
    installationIdKey: installation_id
    privateKeyKey: private_key
```

### SSH authentication

SSH remains the default for backward compatibility. Its Secret must contain an
OpenSSH private key and verified host keys:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-com-git
type: Opaque
stringData:
  private-key: |-
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  known-hosts: |-
    github.com ssh-ed25519 <verified-github-host-key>
```

Use an SSH repository URL and select the mode explicitly when desired:

```yaml
site:
  repository: git@github.com:your-org/example.com.git

gitCredentials:
  authentication: ssh
  secretName: example-com-git
```

Store real credentials in 1Password; do not commit them. Obtain and verify
GitHub's current host keys from GitHub's documentation rather than copying the
placeholder above.

## Configure builds

Each build item has its own container image. `workingDirectory` is relative to
the repository root, `outputDirectory` is relative to that working directory,
and `path` is relative to the hosted site root.

```yaml
build:
  - name: main
    image:
      repository: node
      tag: 22-alpine
      pullPolicy: IfNotPresent
    workingDirectory: apps/web
    command: npm ci && npm run build
    outputDirectory: dist
    path: .

  - name: docs
    image:
      repository: node
      tag: 20-alpine
      pullPolicy: IfNotPresent
    workingDirectory: apps/docs
    command: npm ci && npm run build
    outputDirectory: build
    path: docs
```

The example publishes `apps/web/dist` at `/` and `apps/docs/build` at `/docs`.
Build tasks run in parallel against separate checkouts of the same revision.
After all tasks succeed, a publication task merges outputs in list order. A
failed workflow leaves the currently served release unchanged.

Build images must provide `/bin/sh`, `cp`, and the tools used by their command.

## Persistent releases and node placement

The chart creates a retained 2 GiB RWO claim by default. To use an existing
claim:

```yaml
persistence:
  existingClaim: example-com-site
```

Pin nginx and Workflow pods to the same node:

```yaml
nodeSelector:
  kubernetes.io/hostname: worker-1
```

You can instead set `workflow.nodeSelector` separately, but it must resolve to
the same node. Workflow-level mutex synchronization prevents two revisions from
publishing concurrently. The volume retains the current and immediately
previous releases.

## Install and publish manually

```sh
helm upgrade --install example-com . \
  --namespace example-com \
  --create-namespace \
  --values examples/example.com.values.yaml
```

The nginx readiness probe remains false until the first successful publication.
Submit the default revision from `site.revision`:

```sh
argo submit --from workflowtemplate/example-com-static-site-build \
  --namespace example-com \
  --watch
```

Or publish an exact commit:

```sh
argo submit --from workflowtemplate/example-com-static-site-build \
  --namespace example-com \
  --parameter revision=<commit-sha> \
  --watch
```

Use the actual generated template name shown by `helm install` notes when the
release or chart name differs.

## GitHub push events

Set `events.enabled` to render a GitHub EventSource, Sensor, webhook Service,
minimal RBAC, and optional Ingress:

```yaml
events:
  enabled: true
  # Set this when the EventBus is not in the site's namespace.
  namespace: argo-events
  github:
    repositories:
      - owner: your-org
        names:
          - example.com
    branch: main
    webhookSecret:
      name: example-com-github-webhook
      key: secret
    ingress:
      enabled: true
      hostname: hooks.example.com
```

The EventSource and Sensor are created in `events.namespace`, which defaults to
the Helm release namespace. The named EventBus and GitHub webhook Secret must
exist in that namespace. The Sensor receives narrowly scoped permission to
create the resulting Workflow in the site's release namespace.

Create `example-com-github-webhook` with a strong random `secret` value in the
events namespace, then configure the GitHub repository webhook with the same
secret, content type `application/json`, the `push` event, and this payload URL:

```text
https://hooks.example.com/push
```

The Sensor accepts pushes only for `events.github.branch` and passes the
payload's immutable `after` commit SHA to the WorkflowTemplate. The EventSource
and Sensor can run on any node because they do not mount the site claim.

## Deployment behavior

nginx serves `/srv/site/current`, an atomic symlink maintained by successful
workflows. Site updates do not restart nginx. The chart creates narrowly scoped
service accounts: Workflow pods may report `workflowtaskresults`, while the
Sensor may read its webhook secret and create Workflow resources.

The default nginx security context runs as UID/GID 101. If a custom nginx image
uses another account, update `nginx.securityContext` and the nginx
`podSecurityContext`. Keep the Workflow `fsGroup` compatible with nginx so
published files remain readable.
