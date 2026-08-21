# Static site Helm chart

This chart serves a private Git repository with nginx. A `git-sync` sidecar
polls a branch, publishes each checkout through an atomic symlink, and shares
the checkout with nginx through a read-only volume mount.

## Prerequisites

- Kubernetes 1.34+
- Argo CD (optional, but expected for this repository layout)
- A Kubernetes Secret containing a read-only GitHub SSH deploy key
- The GitHub SSH host key in the same Secret

The chart consumes an existing Secret; it does not create a 1Password
`OnePasswordItem`. Configure the 1Password Operator to produce a Secret like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-com-git
type: Opaque
stringData:
  ssh: |-
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  known-hosts: |-
    github.com ssh-ed25519 <verified-github-host-key>
```

Store the real values in 1Password. Do not commit the private key. Obtain and
verify GitHub's current host keys from GitHub's documentation rather than
copying the placeholder above.

Create two fields on the 1Password item named `ssh` and `known-hosts`. Then
copy `examples/onepassword-item.yaml` into the site's Argo CD configuration and
set `spec.itemPath` to that item. Its `metadata.name` must match
`gitCredentials.secretName`.

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
