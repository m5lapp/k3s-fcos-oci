# Free K3s Cluster on Fedora CoreOS on Oracle Cloud Infrastructure (OCI)

This project is based on the [k3s-cluster-on-oracle-cloud-infrastructure](https://github.com/r0b2g1t/k3s-cluster-on-oracle-cloud-infrastructure) project which aims to automatically deploy a K3s cluster with four nodes which is composed only of always free infrastructure resources on Oracle Cloud Infrastructure (OCI).

Unfortunately the K3OS project that that project uses as the Operating System was deprecated in 2022. Therefore, this project aims to use Fedora CoreOS as the underlying host OS. Similar to K3OS, Fedora CoreOS is a lightweight, automatically updating and immutable OS and is therefore a great alternative to K3OS.

The deployment is initially done by Terraform, but unfortunately, manual work is currently required to install the Fedora CoreOS Operating System over the initial OS and then install K3s on top of that.

## Architecture

The cluster infrastructure is based on four Nodes; two server nodes and two agent nodes for workloads. A load balancer distributes incoming traffic to workloads on the nodes on port 443. The server and agent Nodes must all be deployed into the same availability domains, additionally, the two agent Nodes can only be deployed into AD-2, this is a limitation of OCI. This is so that the boot volumes can be mounted between the different Nodes in order to install Fedora CoreOS, which cannot happen across different availability domains. The cluster uses the [Longhorn](https://longhorn.io) storage solution, which uses the block storage of the OCI instances and allows for Kubernetes persistent volumes to be created out of this storage pool. The following diagram give an overview of the infrastructure.

<p align="center"><img src="diagram/k3s_oci.png" /></p>

Network Security Groups are used to allow external access to the cluster on ports 22 (SSH), 80 and 443 (HTTP(S)), and 6443/6444 (Kubectl).

## Configuration

First of all, you need to setup some environment variables which are needed by the OCI Terraform provider. The [Oracle Cloud Infrastructure documentation](https://docs.oracle.com/en-us/iaas/developer-tutorials/tutorials/tf-provider/01-summary.htm) gives a good overview of where the IDs and information are located and also explains how to set up Terraform.

```sh
export TF_VAR_compartment_id="<COMPARTMENT_ID>"
export TF_VAR_region="<REGION_NAME>"
export TF_VAR_tenancy_ocid="<TENANCY_OICD>"
export TF_VAR_user_ocid="<USER_OICD>"
export TF_VAR_fingerprint="<RSA_FINGERPRINT>"
export TF_VAR_private_key_path="<PATH_TO_YOUR_PRIVATE_KEY>"
export TF_VAR_ssh_authorized_keys='["<SSH_PUBLIC_KEY>"]'
export TF_VAR_domain_name="example.com"
```

If you are deploying to a region other than uk-london-1, then you will also need to configure the init_server_image and init_agent_image variables in the same way as those above and set them to the OCID of the [Oracle-Linux-9.4-aarch64-2024.11.30-0](https://docs.oracle.com/en-us/iaas/images/oracle-linux-9x/oracle-linux-9-4-aarch64-2024-11-30-0.htm) and [Oracle-Linux-9.4-Minimal-2024.09.30-0](https://docs.oracle.com/iaas/images/oracle-linux-9x/oracle-linux-9-4-minimal-2024-09-30-0.htm) images respectively for your region of choice.

## Initial Deployment

Deploying the initial infrastructure is a straight forward process as follows. There are [Taskfile](https://taskfile.dev/) build targets available if you prefer and have Taskfile installed.

```sh
#  Firstly, start with a Terraform init:
terraform init

# Secondly, create a Terraform plan:
terraform plan -out .tfplan

# And finally, apply the plan:
terraform apply .tfplan
```

After a couple of minutes, the OCI network and compute instances will have been created and be up and running. They can then be connected to via SSH to install Fedora CoreOS, and subsequently, K3s, manually. The default username is `opc`.

```sh
ssh -i ~/.ssh/[YOUR_KEY_FILE] opc@[SERVER_0_PUBLIC_IP]
```

Note that it's very common to receive the error `Error: 500-InternalError, Out of host capacity` when trying to provision the two 12GB Ampere control plane nodes. This is because there is very rarely free capacity in the Oracle data centres that is available for use by free-tier customers. If you see this message, then you either have to wait and try again later, or you might want to try changing the `availability_domain` value to a different availability domain in `terraform/compute/main.tf` for the two control plane nodes, or reducing the amount of RAM requested towards the bottom of `terraform/compute/variables.tf`. Alternatively, you can upgrade to a PAYG plan which gives you a higher priority when provisioning compute resources.

## Fedora CoreOS installation

TODO: Come up with a nice way to generate Fedora CoreOS Butane files via Terraform and provision the nodes more easily/automatically.

Fedora CoreOS can be installed over the top of the existing nodes we have provisioned, but it requires quite a bit of manual work. Based on [this Medium article by Terrance Siu](https://medium.com/@terrancesiu/%E5%B0%86oracle-cloud%E7%9A%84vm%E6%93%8D%E4%BD%9C%E7%B3%BB%E7%BB%9F%E6%9B%BF%E6%8D%A2%E4%B8%BAfedora-coreos-cc9861023b89) (Google Translate does a good enough job if you want to translate it), we will essentially detach the boot volume from one node, then attach it to another node and do the installation from there, before unmounting it and attaching it back to the original node.

Fedora CoreOS is installed from a [Butane file](https://docs.fedoraproject.org/en-US/fedora-coreos/producing-ign/) which contains YAML configuration for the OS. After you have deployed the infrastructure via Terraform, the Butane file for each Node will have been generated for you and added onto each Node in the `/home/opc/` directory.

The general process looks like as follows. For simplicity, I will refer to server-0, server-1, agent-0 and agent-1 as node 1, node 2, node 3 and node 4 respectively.

1. In the OCI GUI, stop nodes 1, 3 and 4.
1. Detach the Boot Volume from each of those three nodes.
1. Attach, in order, the three boot volumes on to node 2. This is under the "Attached block volumes" section of the instance. Select `Paravirtualized` for the attachment type and `Read/Write` for the Access mode.
1. You can use `watch lsblk` on node 2 to monitor the detection of each boot volume as it is attached. They will be detected as sdb, sdc and sdd respectively.
1. Podman should already be installed, if not, install it with `sudo dnf install podman`.
1. As per the fedora_coreos/commands.sh file, for each of the three nodes:
    1. Generate the Ignition file from the Butane file if needed (though it should already have been done for you):
       
       ```sh
       podman container run --interactive \
           --rm quay.io/coreos/butane:release \
           --pretty --strict < k3s-server-0.bu > k3s-server-0.bu.ign
       ```

    1. Wipe the file system for the corresponding attached volume with `sudo wipefs -a /dev/sd[bcd]`.
    1. Run the appropriate command for the architecture of the new node (`aarch64` or `x86_64`) as per the fedora_coreos/commands.sh file.

       ```sh
       sudo podman run --pull=always --privileged --rm \
           -v /dev:/dev -v /run/udev:/run/udev -v .:/data -w /data \
           quay.io/coreos/coreos-installer:release \
           install /dev/sdb --architecture aarch64 -i k3s-server-0.bu.ign
       ```

1. Detach the three boot volumes (under "Attached block volumes").
1. Attach each boot volume (under Boot Volumes) back to its original VM instance.
1. Start nodes 1, 3 and 4 up again.
1. SSH onto each of nodes 1, 3 and 4 and check everything looks OK. The default username is `core`, unless you configured something else.
1. Repeat all the above steps to install Fedora CoreOS on node 2 from one of the other nodes (node 1 is probably the best option).

## K3s Installation

To install K3s, the `install_k3s.sh` script should be run on each Node. The script should have been installed as part of the Fedora CoreOS installation and should already be tailored specifically to install K3s on the specific Node that it is on. The script on the k3s-server-0 Node MUST be run first as this initialises the cluster. After that, the script can be run on any of the other Nodes, though it's best to do the remaining server Nodes first. The token is the value that was previously generated and printed out by Terraform and must be the same across all of the Nodes.

If you want to access the server from outside of the Virtual Cloud Network (VCN), then you should set the `--tls-san` flag for any routes you wish to use. If you don't have a domain name to use, then the public IP address of the k3s-server-0 node on its own is fine. It's a good idea to have a k3s-control-plane.example.com DNS entry that points to both the k3s-server-0 and the k3s-server-1 public IP addresses for high availability.

By default, the agent nodes will be installed with a label/taint pair that prevent non-DaemonSet workloads from being scheduled on them. This is because the agent Nodes in the free tier are very low resourced and so a lot of workloads can overwhelm the Nodes and cause them to become unresponsive. To avoid this, we can use a nodeAffinity so that we only schedule workloads that we know will not cause issues as shown below. Note that DaemonSets will still be scheduled on the agent Nodes. The taint_low_resource_nodes boolean Terraform variable can be used to toggle whether or not the script will taint the agents or not.

```yaml
...
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-restriction.example.com/low-resource
            operator: In
            values:
            - "true"
...
```

For information, the basic commands that the `install_k3s.sh` script files use look like this for each of the Node types.

```sh
# k3s-server-0 (to bootstrap the cluster).
curl -sfL https://get.k3s.io | \
    sh -s - \
    server \
    --cluster-init \
    --node-ip 10.0.0.10 \
    --token "[RANDOM_TOKEN_GENERATED_BY_TERRAFORM]" \
    --tls-san [SERVER_0_PUBLIC_IP] \
    --tls-san k3s-server-0 \
    --tls-san k3s-server-0.example.com \
    --tls-san k3s-control-plane.example.com

# k3s-server-1 (join the cluster as a second control-plane Node).
curl -sfL https://get.k3s.io | \
    sh -s - \
    server \
    --server https://10.0.0.10:6443 \
    --token "[RANDOM_TOKEN_GENERATED_BY_TERRAFORM]" \
    --tls-san [SERVER_1_PUBLIC_IP] \
    --tls-san k3s-server-1 \
    --tls-san k3s-server-1.example.com

# Add the agent Nodes.
curl -sfL https://get.k3s.io | \
    sh -s - \
    agent \
    --server https://10.0.0.10:6443 \
    --token "[RANDOM_TOKEN_GENERATED_BY_TERRAFORM]" \
    --node-label "node-restriction.example.com/low-resource=true" \
    --node-taint "node-restriction.example.com/low-resource=true:PreferNoSchedule"
```

Finally, if you want to be able to use Kubectl from externally, copy the config off of k3s-server-0 to `~/.kube/config`, then update the `server:` line to change the IP address from 127.0.0.1 to either the control plane DNS entry that you set up previously, or the public IP of either k3s-server-0 or k3s-server-1.

```sh
scp core@<SERVER_NODE_0_PUBLIC_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config

sed -i 's/127.0.0.1/EXTERNAL_IP_OR_DNS_ENTRY/' ~/.kube/config
```

You can now use `kubectl` on your local machine to manage your cluster and check the nodes:

```sh
kubectl get nodes -o wide
```

### Renewing Client Certificates

By default, the client credentials used for accessing the cluster via Kubectl will be rotated automatically after a year. When this happens, you will no-longer be able to use Kubectl to access the cluster and will receive an error message like this:

```
E0120 23:42:52.889590   28828 memcache.go:265] couldn't get current server API group list: the server has asked for the client to provide credentials
E0120 23:42:52.897144   28828 memcache.go:265] couldn't get current server API group list: the server has asked for the client to provide credentials
E0120 23:42:52.904849   28828 memcache.go:265] couldn't get current server API group list: the server has asked for the client to provide credentials
E0120 23:42:52.910813   28828 memcache.go:265] couldn't get current server API group list: the server has asked for the client to provide credentials
E0120 23:42:52.917023   28828 memcache.go:265] couldn't get current server API group list: the server has asked for the client to provide credentials
error: You must be logged in to the server (the server has asked for the client to provide credentials)
```

The solution to this is simply to get the new credentials from `/etc/rancher/k3s/k3s.yaml` again on one of the API server nodes.

### Modifying a K3s Installation

If you need to modify the options that a server was installed with, then as per [this Reddit post](https://www.reddit.com/r/kubernetes/comments/pwmay3/modifying_running_k3s_cluster_configuration/), you can edit the command-line options in the systemd unit file at `/etc/systemd/system/k3s.service` and then run `sudo systemctl daemon-reload` before restarting K3s with `sudo systemctl restart k3s`.

## Further Reading

The `docs/` directory contains documentation for further reading and extending the cluster's capabilities with the following:

 * [CI/CD](/docs/cicd.md) - Automating the deployment of resources into the cluster
 * [Ingress](/docs/ingress.md) - Receiving traffic into the cluster with Traefik
 * [Monitoring and Observability](/docs/monitoring_and_observability.md) - Get insights into the health and state of the cluster
 * [Service Mesh](/docs/service_mesh.md) - Leveraging Linkerd to handle in-cluster networking
 * [Secret Management](/docs/secret_management.md) - Securely deploying and using Secrets in the cluster
 * [Storage](/docs/storage.md) - Leveraging Longhorn for distributed block storage
 * [Upgrades](/docs/upgrades.md) - Keeping the cluster up-to-date

## TODOs

 * Automate the deployment of Fedora CoreOS and K3s
 * Terraform Load Balancer deployment

