# Static site Helm chart

This chart builds a private Git repository with Tekton Pipelines and serves the
published static files with nginx. Build tasks may use different images and run
in parallel. A successful PipelineRun assembles their outputs on a persistent
volume and atomically switches nginx to the new release.

Repositories without a build step are also supported: leave `build` empty and
the Pipeline publishes the checked-out repository contents directly.

## Prerequisites

- Kubernetes with a filesystem-backed `ReadWriteOnce` storage class
- Tekton Pipelines
- Tekton Triggers and its core interceptors when `triggers.enabled` is true
- A node on which nginx and every TaskRun pod can be scheduled together
- A GitHub App with read-only Contents access, or a read-only SSH deploy key
- A Kubernetes Secret containing the selected authentication credentials

`ReadWriteOnce` permits the claim to be mounted by multiple pods on one node.
Set the same node selector for nginx and PipelineRuns. Trigger-created
PipelineRuns use `pipeline.nodeSelector`, falling back to the chart's top-level
`nodeSelector`.

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

Each build TaskRun executes `git-sync` before its build step. `git-sync` uses
the App private key to mint a short-lived installation token. The credential
volume is mounted only into that step. To use an existing Secret, leave
`onePassword.enabled: false` and set `gitCredentials.secretName`.

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
GitHub's current host keys rather than copying the placeholder above.

## Configure builds

Each build item becomes an independent Tekton PipelineTask with its own
checkout. `workingDirectory` is relative to the repository root,
`outputDirectory` is relative to that working directory, and `path` is relative
to the hosted site root.

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
Build TaskRuns execute in parallel. The publish Task runs only after every build
succeeds, and the `finally` cleanup Task runs after success or failure. Build
images must provide `/bin/sh`, `cp`, and the tools used by their command.

## Persistent releases and node placement

The chart creates a retained 2 GiB RWO claim by default. To use an existing
claim:

```yaml
persistence:
  existingClaim: example-com-site
```

Pin nginx and trigger-created PipelineRuns to the same node:

```yaml
nodeSelector:
  kubernetes.io/hostname: worker-1
```

You can set `pipeline.nodeSelector` separately, but it must resolve to the same
node as nginx. Every PipelineTask binds the same `site` Workspace, allowing
Tekton's Affinity Assistant to co-schedule TaskRuns that share the RWO claim.

The publish step takes an advisory lock on the shared filesystem. Concurrent
PipelineRuns may build in parallel, but publication and release pruning are
serialized. The lock is automatically released if the process exits. The
volume retains the current and immediately previous successful releases.

## Install and publish manually

```sh
helm upgrade --install example-com . \
  --namespace example-com \
  --create-namespace \
  --values examples/example.com.values.yaml
```

The nginx readiness probe remains false until the first successful publication.
Start the default revision:

```sh
tkn pipeline start example-com-static-site-build \
  --namespace example-com \
  --param revision=main \
  --workspace name=site,claimName=example-com-static-site-site \
  --serviceaccount example-com-static-site-pipeline \
  --showlog
```

Use the generated names shown by `helm install` notes when the release or chart
name differs. For manual PipelineRuns that require custom scheduling, supply a
Tekton pod template equivalent to `pipeline.nodeSelector`, `affinity`, and
`tolerations`.

## GitHub push triggers

Set `triggers.enabled` to render a Tekton EventListener, minimal RBAC, and an
optional Ingress:

```yaml
triggers:
  enabled: true
  namespace: tekton-triggers
  github:
    branch: main
    webhookSecret:
      name: example-com-github-webhook
      key: secret
    ingress:
      enabled: true
      hostname: hooks.example.com
```

The namespace must already exist and contain the webhook Secret. Create it with
a strong random `secret` value, then configure the GitHub repository webhook
with the same secret, content type `application/json`, the `push` event, and:

```text
https://hooks.example.com/push
```

The GitHub interceptor validates the webhook HMAC and accepts only push events.
The CEL interceptor accepts only `triggers.github.branch`. The binding passes
the payload's immutable `after` commit SHA into a PipelineRun. The EventListener
receives permission only to read its webhook Secret and create PipelineRuns in
the site's release namespace.

GitHub App credentials are used only for repository checkout. Tekton Triggers
does not need the App private key because the webhook is configured manually.

## Deployment behavior

nginx serves `/srv/site/current`, an atomic symlink maintained by successful
PipelineRuns. Site updates do not restart nginx. The Pipeline service account
does not receive Kubernetes API permissions and does not automount a token; the
Trigger service account has only the narrowly scoped access described above.

The default nginx security context runs as UID/GID 101. If a custom nginx image
uses another account, update `nginx.securityContext` and `podSecurityContext`.
Keep `pipeline.podSecurityContext.fsGroup` compatible with nginx so published
files remain readable.
