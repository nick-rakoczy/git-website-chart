# Static site Helm chart

This chart serves a private Git repository with nginx. A `git-sync` sidecar
polls a branch, publishes each checkout through an atomic symlink, and shares
the checkout with nginx through a read-only volume mount.

## Prerequisites

- Kubernetes 1.34+
- Argo CD (optional, but expected for this repository layout)
- A GitHub App with read-only Contents access, or a read-only GitHub SSH
  deploy key
- A Kubernetes Secret containing the selected authentication credentials

The chart can create a 1Password `OnePasswordItem`, or consume an existing
Secret.

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

`git-sync` uses the App private key to mint and refresh short-lived
installation tokens automatically. To use an existing Secret, leave
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

SSH remains the default authentication mode for backward compatibility. Its
Secret must look like:

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

Store the real values in 1Password. Do not commit the private key. Obtain and
verify GitHub's current host keys from GitHub's documentation rather than
copying the placeholder above.

Use a 1Password **SSH Key** item and add a custom text field named
`known-hosts`. The operator normalizes the built-in `private key` field to the
Secret key `private-key`; `known-hosts` keeps its name. Enable provisioning
directly from the chart with:

```yaml
gitCredentials:
  authentication: ssh
  # Optional; defaults to <release fullname>-git.
  secretName: example-com-git
  onePassword:
    enabled: true
    itemPath: vaults/Kubernetes/items/example-com-git
```

The operator creates a Secret with the same name as the generated
`OnePasswordItem`.

If an existing Secret uses different key names, override them explicitly:

```yaml
gitCredentials:
  privateKeyKey: private-key
  knownHostsKey: known-hosts
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
namespace, and values file.

## Deployment behavior

Each pod independently polls the configured branch. A push does not require an
Argo CD sync or a pod restart. During startup the nginx readiness probe fails
until the configured index file is present. Set `replicaCount` above one when
you want pod-restart availability as well as atomic in-pod content updates.

The default nginx security context runs as UID/GID 101, matching the official
nginx Alpine image. If a custom nginx image uses a different non-root account,
override `nginx.securityContext.runAsUser`, `runAsGroup`, and the pod
`fsGroup` to match it.
