# CI/CD

# Flux CD
[Flux](https://fluxcd.io/) is a CNCF-graduated, open-source project that allows for continuous delivery of software into a Kubernetes cluster by keeping it in sync with a range of configuration sources such as Git or Helm repositories or an S3 bucket.

## Installation
### Install the Flux CLI
In order to bootstrap and later interact with Flux, the flux CLI should be [installed](https://fluxcd.io/flux/installation/#install-the-flux-cli). The easiest way to do this to download and run the `install.sh` script that Flux supply:

```bash
curl -s https://fluxcd.io/install.sh | sudo bash

# Alternatively, specify a particular directory to install into.
curl -s https://fluxcd.io/install.sh | BIN_DIR="/usr/local/bin" sudo bash

# Optionally, you can also install bash completion for Flux globally if desired
# by running the following command:
flux completion bash | sudo tee /etc/bash_completion.d/flux > /dev/null
```

Once the CLI is installed, run `flux check --pre` to verify it and check that the cluster meets the prerequisites.

### Create the Flux Git Repository
There are [multiple ways](https://fluxcd.io/flux/installation/bootstrap/) that Flux can be boostrapped depending on what source is used to pull the cluster state from. The methods are broadly similar, but here we will focus on [using Github](https://fluxcd.io/flux/installation/bootstrap/github/) to host the cluster state.

The first thing to do is to create a Git repository on Github for storing the Flux configuration and the YAML manifests of the cluster's resources. A reasonable name for this, which we will use throughout this guide, is `k8s-cluster-state`. 

Next, create a **Personal Access Token (classic)** in the [Github UI](https://github.com/settings/tokens) with all of the available "admin" and "repo" permissions assigned to it. Once generated, save the token into an environment variable called GITHUB_TOKEN by running `read GITHUB_TOKEN` and then pasting the value in.

Once created, the repository does not HAVE to be configured before it's used, Flux can do this for us, but it provides much more power and control if you do some configuration ahead of time. There are [various ways](https://fluxcd.io/flux/guides/repository-structure/) that the repository can be structured; for simplicity, and because it fits most use-cases, the monorepo approach will be used in this guide.

Using the [flux2-kustomize-helm-example repository](https://github.com/fluxcd/flux2-kustomize-helm-example/tree/main) as an example, we will create a file and directory structure like the following:

```
├── clusters
│   └── prod
│       ├── infra-10-cluster-config-kustomization.yaml
│       ├── infra-20-security-kustomization.yaml
│       ├── infra-30-service-mesh-kustomization.yaml
│       ├── infra-40-storage-kustomization.yaml
│       ├── infra-50-apps-kustomization.yaml
│       ├── workloads-kustomization.yaml
│       └── flux-system
│           └── kustomization.yaml
├── infrastructure
│   ├── 10-cluster-config
│   │   ├── crds.yaml
│   │   ├── kustomization.yaml
│   │   └── namespaces.yaml
│   ├── 20-security
│   │   ├── cert-manager.yaml
│   │   ├── helm-repos.yaml
│   │   ├── kustomization.yaml
│   │   ├── sealed-secrets.yaml
│   │   └── trust-manager.yaml
│   ├── 30-service-mesh
│   │   ├── kustomization.yaml
│   │   └── linkerd.yaml
│   ├── 40-storage
│   │   └── longhorn.yaml
│   └── 50-apps
│       ├── kustomization.yaml
│       ├── monitoring
│       │   ├── jaeger-tracing.yaml
│       │   └── kube-prometheus-stack.yaml
│       └── system-upgrade-controller.yaml
├── README.md
└── workloads
    ├── base
    │   └── app2
    │       ├── app2.yaml
    │       └── kustomization.yaml
    └── prod
        ├── app1
        │   └── app1.yaml
        └── app2
            ├── app2-patches.yaml
            └── kustomization.yaml
```

The idea here is that for each cluster (in this case there is just *prod*), there is:

 * A `clusters/prod/flux-system/` directory which contains a `kustomization.yaml` file that pulls in the configuration that Flux will generate later and also contains patches to further configure the Flux installation (such as annotating the flux-system Namespace here):
    ```yaml
    ---
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    resources:
    - gotk-components.yaml
    - gotk-sync.yaml
    patches:
    - target:
        kind: Namespace
        name: flux-system
      patch: |
        # To include a / in the key name, it must be encoded as ~1.
        - op: add
          path: /metadata/annotations/linkerd.io~1inject
          value: enabled
    ```
 * A `clusters/prod/` directory containing files defining [Flux Kustomizations](https://fluxcd.io/flux/components/kustomize/kustomizations/) that divide the resources to be deployed up into logical groupings which can be customised to meet your own requirements.
    * It's a good idea to number the Kustomizations to make it obvious in which order they should be deployed. The numbers here go up in tens to allow for other Kustomizations to be added in the future between existing ones.
    * Later Kustomizations can use the `.spec.dependsOn` field to define which Kustomizations must be successfully applied before it. For instance, if the `infra-30-service-mesh` Kustomization depends on a certificate manager that is deployed in the `infra-20-security` Kustomization, then its Kustomization might look like this:
        ```yaml
        apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: kustomization
        metadata:
            name: infra-30-service-mesh
            namespace: flux-system
        spec:
        dependsOn:
        - name: infra-20-security
        force: false
        interval: 1h
        path: ./infrastructure/30-service-mesh/
        prune: true
        retryInterval: 1m0s
        sourceRef:
            kind: GitRepository
            name: flux-system
        suspend: false
        timeout: 5m0s
        wait: true
        ```
    * The `.spec.path` field in each Kustomization defines the path from the root of the repository where the [`kustomization.yaml`](https://fluxcd.io/flux/components/kustomize/kustomizations/#generating-a-kustomizationyaml-file) for the Kustomization (or some plain YAML manifests for which a `kustomization.yaml` file will be generated) live.
 * For each "`infra`" Kustomization, the `.spec.path` field refers to a directory under `infrastructure/`. These are not in a parent directory for the cluster (e.g. `prod/`) because they can generally be shared between different clusters without modification. If modification is required, then the `infrastructure/` directory can be configured in the same way as the `workloads/prod/app2/` directory to apply patches to base manifest files as described in the next point.
 * In the `workloads/` directory, resources can be deployed in one of two ways:
    * As in the case of **app1** in the example, the stand-alone YAML manifests can be added to the `workloads/prod/app1/` directory as normal along with a `kustomization.yaml` file if desired.
    * As in the case of **app2** in the example, the main resource YAML manifests can be kept in a directory under `workloads/base/app2/` and then any cluster-specific changes can be added to skeleton YAML manifests in the `workloads/prod/app2/` directory along with a kustomization.yaml that contains something like this which will patch the app2 HelmRelase:
        ```yaml
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources:
        - ../../base/app2/
        patches:
        - path: app2-patches.yaml
        target:
            kind: HelmRelease
            name: app2
        ```

### Bootstrap Flux with Github
Once the repository has been created and configured, Flux can be bootstrapped with the following command; be sure to add your own Github user and repository name. This will check in some additional configuration, deploy the Flux components and synchronise the cluster state repository into the cluster. Be sure that your Kubectl is using the correct context before running the bootstrap command; this can be configured with the `--context CONTEXT` flag if desired.

```bash
flux bootstrap github \
    --token-auth \
    --owner m5lapp \
    --repository k8s-cluster-state \
    --branch main \
    --path=clusters/prod/ \
    --private true \
    --personal
```

