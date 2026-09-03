# Static site Helm chart

This chart clones and builds a private Git repository in Kubernetes init
containers, then serves the result with nginx. It needs no workflow controller,
event controller, persistent volume, or build service account.

Leave `build` empty to serve the repository contents directly. When builds are
configured, each item gets its own copy of the checkout and publishes its output
into the nginx site root.

## Prerequisites

- Kubernetes 1.34+
- A GitHub App with read-only Contents access, or a read-only GitHub SSH deploy key
- A Kubernetes Secret containing the selected authentication credentials

The chart can create a 1Password `OnePasswordItem`, or consume an existing
Secret.

## Configure builds

Build items run sequentially because Kubernetes init containers are ordered.
`workingDirectory` is relative to the repository root, `outputDirectory` is
relative to that working directory, and `path` is relative to the hosted site
root.

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

This publishes `apps/web/dist` at `/` and `apps/docs/build` at `/docs`. Each
build starts from a separate copy of the same checkout, so one build cannot
modify another build's source. Outputs are copied in list order. Later items can
replace files written by earlier items.

Build images must provide `/bin/sh`, `cp`, and the tools used by their command.
The pod stays in its init phase if a clone or build fails, so nginx never serves
a partial result.

To serve repository files without building them, keep the default:

```yaml
build: []
```

## GitHub App authentication

Install the App on the required repositories with read-only Contents access.
The Secret must contain the App and installation IDs plus its private key:

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

Use an HTTPS repository URL:

```yaml
site:
  repository: https://github.com/your-org/example.com.git

gitCredentials:
  authentication: githubApp
  secretName: static-sites-git
```

The one-time `git-sync` init container uses the App private key to mint an
installation token. Field names can be overridden under
`gitCredentials.githubApp`.

## SSH authentication

SSH remains the default authentication mode. Its Secret must look like:

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

Obtain and verify GitHub's current host keys from GitHub's documentation. Do
not copy the placeholder above.

```yaml
site:
  repository: git@github.com:your-org/example.com.git

gitCredentials:
  authentication: ssh
  secretName: example-com-git
```

To provision either credential type through 1Password, enable the bundled
`OnePasswordItem`:

```yaml
gitCredentials:
  onePassword:
    enabled: true
    itemPath: vaults/Kubernetes/items/example-com-git
```

## Install or render

```sh
helm upgrade --install example-com . \
  --namespace example-com \
  --create-namespace \
  --values examples/example.com.values.yaml
```

```sh
helm template example-com . \
  --namespace example-com \
  --values examples/example.com.values.yaml
```

For Argo CD, copy `examples/application.yaml` and adjust its repository,
namespace, and values file. Argo CD is only acting as the Helm reconciler here.
The chart does not use Argo Workflows or Argo Events.

## Deployment behavior

The clone and build happen once per pod startup. Use an immutable commit SHA in
`site.revision` and update it through Helm or GitOps to publish a new version.
Changing `site.revision`, a build command, or a build image changes the pod
template and starts a rolling update.

A branch name such as `main` resolves only when Kubernetes creates a new pod.
Pushing to that branch does not change the Deployment, so it does not trigger a
build. Restart the Deployment or change a pod-template value if branch-based
deployments are required.

Each replica has its own `emptyDir` volumes and performs its own clone and
build. The rolling update keeps the old pod available while the replacement
builds. The default nginx security context runs as UID/GID 101. If a custom
nginx image uses another account, update `nginx.securityContext` and
`podSecurityContext` together.
