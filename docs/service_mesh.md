# Cilium Service Mesh
Unfortunately the Cilium service mesh is too resource intensive to run on the Oracle free-tier cluster.

## Installation
As per the [Cilium documentation](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-cilium), to install Cilium on a K3s cluster, the cluster needs to  have been installed with the following flags set:

 * `--disable-network-policy`
 * `--flannel-backend=none` 

Next, [install the Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli) as described in the documentation and then use that to install Cilium into the cluster as follows:

```bash
export CILIUM_VERSION=$(curl --silent https://raw.githubusercontent.com/cilium/cilium/main/stable.txt)
cilium install --version ${CILIUM_VERSION}

# Test the installation was successful.
cilium status --wait
cilium connectivity test
```

# Linkerd Service Mesh

## Installation
The free-tier, four-node cluster does not really have sufficient resources available to run a service mesh like Cilium or Istio. Particularly it seems to struggle with a lack of CPU resources. [Linkerd](https://linkerd.io/2.14/features/automatic-mtls/#operational-concerns) however is much more lightweight and works really well.

As per the [Linkerd documentation](https://linkerd.io/2.14/features/automatic-mtls/#operational-concerns), the default installation requires the trust anchor and cluster issuer certificate and key to be [manually rotated](https://linkerd.io/2.14/tasks/manually-rotating-control-plane-tls-credentials/) every year. It therefore might be preferable to install Linkerd with a longer-lasting, manually-created trust anchor certificate and [use Cert Manager](https://linkerd.io/2.14/tasks/automatically-rotating-control-plane-tls-credentials/) to rotate the cluster issuer certificate and key. The installation process therefore is as follows:

1. Install Cert Manager as described in the section above
1. Install the [step-cli](https://smallstep.com/docs/step-cli/installation/) tool for generating the required certificates
1. Create the linkerd namespace: `kubectl create namespace linkerd`
1. Generate the trust anchor key pair (valid here for ten years) and save them into a Kubernetes Secret:
   ```sh
   mkdir certs/

   step certificate create root.linkerd.cluster.local certs/ca.crt certs/ca.key \
       --profile root-ca --no-password --insecure --not-after 87600h

   kubectl create secret tls linkerd-trust-anchor \
       --cert certs/ca.crt --key certs/ca.key --namespace linkerd
   ```
1. Create a Cert Manager Issuer that references the new Secret:
   ```sh
   kubectl apply -f services/linkerd/trust_anchor_issuer.yaml
   ```
1. Create a Cert Manager Certificate that references the new Issuer and check that the identity issuer certificate then gets created successfully
   ```sh
   kubectl apply -f services/linkerd/identity_issuer_certificate.yaml

   kubectl get secret -n linkerd linkerd-identity-issuer -o yaml
   ```
1. [Install](https://linkerd.io/2.14/getting-started/#step-1-install-the-cli) the Linkerd CLI
    1. Set up command completion if desired with `linkerd completion bash > /etc/bash_completion.d/linkerd`. Note that you may need to do `sudo -i` to run this
1. Check everything is configured correctly with `linkerd check --pre`. This will likely fail in two places due to the linkerd namespace already existing; these failures can be ignored
1. Install the Linkerd CRDs and then the control plane making sure to pass the --identity-external-issuer flag so that it uses the Cert Manager-managed Secrets. Again, a warning will be printed out due to the linkerd namespace already existing, but everything should work OK
   ```sh
   linkerd install --crds | kubectl apply -f -
   linkerd install --identity-external-issuer | kubectl apply -f -
   ```
1. Check the installation with `linkerd check`. As the issuer certificate is configured to expire after 48 hours and be rotated 25 hours before then, this will warn that the issuer certificate is not valid for at least 60 days. Again, this warning [can be safely ignored](https://github.com/linkerd/website/issues/1342)
1. Finally [add your services](https://linkerd.io/2.14/tasks/adding-your-service/) to the Linkerd mesh
1. Optionally, you may wish to install the viz extension for observability and visualisation of the Linkerd service mesh:
   ```sh
   linkerd viz install | kubectl apply -f -
   linkerd check
   linkerd viz dashboard &
   ```

### Upgrades
Upgrading the CLI is as simple as [running the install command](https://linkerd.io/2.14/getting-started/#step-1-install-the-cli) again.

To [upgrade the Linkerd control plane](https://linkerd.io/2.14/tasks/upgrade/#with-the-linkerd-cli), use the `linkerd upgrade` command:

```bash
linkerd upgrade --crds | kubectl apply -f -
linkerd upgrade | kubectl apply -f -

# Prune any resources that were present in the previous version but should not
# be present in this one.
linkerd prune | kubectl delete -f -
```

## Terminating Meshed Jobs
One [side-effect](https://github.com/kubernetes/kubernetes/issues/25908) of running a sidecar like Linkerd's proxy with a Job in Kubernetes is that the Job will continue to run even after the main container has finished due to the Linkerd proxy container never terminating. For a CronJob, this also means that as the first instance of the Job never finishes, all subsequent instances will get stuck in the PodInitializing state. There are [a number of workarounds](https://itnext.io/three-ways-to-use-linkerd-with-kubernetes-jobs-c12ccc6d4c7c) for this all with their own pros and cons as described below.

### Option 1
The simplest workaround for this issue is to simply remove any CronJob or Job Pods from the mesh by adding the `linkerd.io/inject: disabled` annotation to the `.spec.template.metadata.annotations` field of a Job or a CronJob's `jobTemplate`. The main downside of this approach is that if the Pod needs to communicate with another Pod on the mesh using mTLS, then this will obviously not work.

### Option 2
Another option is to call the Linkerd admin `shutdown` hook from the main container in the Pod once the main command has completed [via the loopback interface](https://github.com/linkerd/linkerd2-proxy/pull/811#issue-775118324) using either cURL or wget.

```bash
# cURL
/app/script.sh && \
CODE = $?; curl -X POST 127.0.0.1:4191/shutdown; exit $CODE

# wget
/app/script.sh && \
CODE=$?; wget --post-data '' 127.0.0.1:4191/shutdown; exit $CODE
```

This works reasonably well, but requires curl or wget to be available in the container. It also creates a coupling between the CronJob or Job manifest and the Linkerd service mesh.

### Option 3
An alternative is to run an instance of the [lemonadehq/controller-sidecars](https://github.com/lemonade-hq/k8s-controller-sidecars) container in the cluster and add a specific annotation to the jobTemplate of any meshed Jobs or CronJobs. To get started, first, install the controller-sidecars Pod into the `kube-system` namespace:

```bash
kubectl apply -f https://raw.githubusercontent.com/lemonade-hq/k8s-controller-sidecars/master/manifest.yml
```

Next, add the `lemonade.com/sidecars: linkerd-proxy` annotation to any CronJobs or Jobs that require it. Note that the value of the annotation is a comma-seperated list of sidecar container names, in this case, just linkerd-proxy. Once the main container in the Pod has completed, the sidecar-controller should then detect this and send a SIGTERM signal to the specified sidecard.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup-data
  namespace: workloads
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        metadata:
          annotations:
            lemonade.com/sidecars: linkerd-proxy 
          labels:
            job: database-backup-data
        spec:
          ...
```

This should have the advantage of having no coupling between the Jobs and the service mesh other than the addition of the annotation. Unfortunately, I have not been able to get this working in this K3s cluster, the main container runs to completion, but the sidecar-controller Pod does not seem to even send the SIGTERM that it's supposed to and the Pod gets stuck in a NotReady status.
