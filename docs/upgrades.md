# Upgrades

## Upgrading K3s
As per the [K3s documentation](https://docs.k3s.io/upgrades/automated), [Rancher's system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) can be used to automate the process of upgrading the K3s components.

To utilise this, first, install the system-upgrade-controller via Kubectl:

```bash
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
```

Next, prepare an upgrade plan based on the example at `services/k3s-upgrade-plan.yaml`. The key thing here is to set the `.spec.version` field to the version you want to upgrade to from [the K3s releases page](https://github.com/k3s-io/k3s/releases). Note that you should not jump up more than one minor version at a time.

Alternatively, for automatic updates to the latest stable version, replace `.spec.version` with `.spec.channel: https://github.com/k3s-io/k3s/releases` and K3s will always be upgraded when a new stable release is available.

Once you have prepared your plan and are ready to perform the upgrade, simply apply the YAML and monitor the upgrade until it completes.

```bash
kubectl apply -f services/k3s-upgrade-plan.yaml

# Watch all the nodes to see the upgrade happen in real time. Here, the first
# control plane node has been successfully upgraded to v1.26.3+k3s1 and the
# second control one is in progress before the server nodes.
watch kubectl get nodes -o wide
# NAME           STATUS                        ROLES                       AGE    VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                        KERNEL-VERSION            CONTAINER-RUNTIME
# k3s-agent-0    Ready                         <none>                      101d   v1.25.5+k3s1   10.0.0.20     <none>        Fedora CoreOS 37.20230322.3.0   6.1.18-200.fc37.x86_64    containerd://1.6.12-k3s1
# k3s-agent-1    Ready                         <none>                      101d   v1.25.5+k3s1   10.0.0.21     <none>        Fedora CoreOS 37.20230322.3.0   6.1.18-200.fc37.x86_64    containerd://1.6.12-k3s1
# k3s-server-0   NotReady,SchedulingDisabled   control-plane,etcd,master   101d   v1.25.5+k3s1   10.0.0.10     <none>        Fedora CoreOS 37.20230322.3.0   6.1.18-200.fc37.aarch64   containerd://1.6.19-k3s1
# k3s-server-1   NotReady                      control-plane,etcd,master   101d   v1.26.3+k3s1   10.0.0.11     <none>        Fedora CoreOS 37.20230322.3.0   6.1.18-200.fc37.aarch64   containerd://1.6.19-k3s1

kubectl -n system-upgrade get plans -o yaml
kubectl -n system-upgrade get jobs -o yaml
```

If you specified a specific K3s version to upgrade to, then the next time you wish to upgrade, you simply need to update the `.spec.version` field in the two Plan definitions and then reapply the YAML file.
