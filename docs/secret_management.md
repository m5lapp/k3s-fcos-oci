# Secret Management

## Sealed Secrets
Bitnami's [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) project allows for secrets to be encrypted using a public key that can be freely distributed within your company or organisation in such a way that the encrypted Secret value could be checked in to a public repository if so desired without fear of the underlying values being exposed. Once deployed to the cluster as part of a SealedSecret custom resource, the secret value is decrypted by a sealed-secrets-controller Pod using a corresponding private key. The controller then deploys the decrypted secret value into the cluster as part of an ordinary Kubernetes Secret resource.

### Installation
In order to seal secrets and otherwise interract with the controller, it is necessary to first install the Sealed Secrets CLI as follows. The latest `KUBESEAL_VERSION` value can be found from the [tags in Github](https://api.github.com/repos/bitnami-labs/sealed-secrets/tags).

```bash
KUBESEAL_VERSION="0.24.4"
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION:?}/kubeseal-${KUBESEAL_VERSION:?}-linux-amd64.tar.gz"

tar -xvzf kubeseal-${KUBESEAL_VERSION:?}-linux-amd64.tar.gz kubeseal

sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm kubeseal*
```

The Sealed Secrets CRDs and controller can be [installed](https://github.com/bitnami-labs/sealed-secrets#installation) via Helm by deploying the following HelmChart resource. The `fullnameOverride` value is required in order to make the Sealed Secrets CLI tool's expected default controller name match the name of the Pod in the cluster.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: sealed-secrets
  namespace: kube-system
spec:
  repo: https://bitnami-labs.github.io/sealed-secrets
  chart: sealed-secrets
  targetNamespace: kube-system
  version: "2.13.3"
  valuesContent: |-
    fullnameOverride: sealed-secrets-controller
```

### Backups
As per the [Sealed Secrets README](https://github.com/bitnami-labs/sealed-secrets#how-can-i-do-a-backup-of-my-sealedsecrets), backing up Sealed Secrets is as simple as making a copy of the encryption keys to a file and then storing it somewhere safe:

```bash
kubectl get secrets -n kube-system \
    -l sealedsecrets.bitnami.com/sealed-secrets-key \
    -o yaml > sealed-secrets-backup.yaml
```

To restore from the backup, simply use kubectl to apply the backup file with the encryption keys back into the cluster, then deploy Sealed Secrets as normal or restart the sealed-secrets-controller Pod if it's already deployed and running.
```bash
kubectl apply -f main.key

# Restart the sealed-secrets-controller Pod if it's already running.
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Usage
If everything was installed as described above, then Kubeseal can be used to seal secrets as follows. It will by default connect to the same cluster as defined by your Kubernetes config file and fetch the certificate to use for encrypting/sealing from a Pod called `sealed-secrets-controller` in the `kube-system` namespace. Alternatively, the `--controller-name` and `--controller-namespace` flags can be used to set these manually if they are different, or, the `--cert string` flag can be used to bypass this and read the certificate for encryption directly from a file or URL.

As per the [scopes section](https://github.com/bitnami-labs/sealed-secrets#scopes) of the Sealed Secrets README file, when a secret is encrypted by kubeseal, it can be done so with any one of three **scopes** using the `--scope string` flag:

 * **strict** (default): The secret must be sealed with exactly the name of the Sealed Secret and the namespace where it will be used. These attributes become part of the encrypted data and thus changing the SealedSecret's name and/or namespace would lead to a "decryption error".
 * **namespace-wide**: You can freely rename the sealed secret within a given namespace.
 * **cluster-wide**: The secret can be unsealed in any namespace and can be given any name.

When using the **strict** scope with the `--raw` flag, the `--name string` flag must be used to specify the name of the SealedSecret and Secret that can use the encrypted value. Similarly, when using the **strict** or **namespace-wide** scopes, the namespace will be derived from either the inputted Secret, the `--namespace string` flag or the Kubernetes default namespace in that order.

Note that if a value is encrypted twice with the same certificate, the resultant encrypted string will always be different each time, you cannot compare the encrypted values for equality.

```bash
# Read the Kubernetes Secret from the file my-secret.yaml and create a
# corresponding SealedSecret from it in the my-sealed-secret-file.yaml file.
kubeseal --secret-file my-secret.yaml --sealed-secret-file my-sealed-secret.yaml

# Generate an encrypted sealed secret value from the file private-key.pem that
# can only be used in a SealedSecret named `private-key` that lives in the
# `my-namespace` namespace, and print it to standard out.
kubeseal --scope strict --raw --name private-key --namespace my-namespace --from-file private-key.pem && echo

# Read a secret value from standard input, seal it and print it to standard
# output. The `namespace-wide` scope means that it can only be unsealed into the
# my-namespace namespace, though the SealedSecret reource can have any name.
echo -n 'Pa55W0rd' | kubeseal --scope namespace-wide --raw --namespace my-namespace --from-file /dev/stdin

# Read a secret value that you write or paste to standard input and seal it.
# The input value can be multi-line and once it has been written you should
# enter the literal value "EOF" on a new line and then hit Enter.
kubeseal --scope cluster-wide --raw --from-file /dev/stdin <<EOF
> Multi
> line
> string
> EOF
```
