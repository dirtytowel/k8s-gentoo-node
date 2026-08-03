My take on "kubernetes the hard way" using gentoo, catalyst, ansible, and a local vagrant worlfow.

# layout

```text
catalyst/                  gentoo catalyst config for building a stage4 tarfile
ansible/                   playbooks and roles for managing a cluster
vagrant/                   generated box/kernel/initramfs/build artifacts for local vagrant dev
Vagrantfile                vagrant cluster vms
Makefile                   helper commands for dev
```

# dependencies

On the host you need roughly:

```sh
docker
vagrant
vagrant-libvirt
libvirt
qemu-img
ansible
mkfs.ext4
tar
virsh
```

you also might as well run:
```sh
make venv #installs python and ansible galaxy dependencies
source ansible/.venv/bin/activate
```
so that you can easily run the ansible shit

# how to build the base image

Build the gentoo stage4 tarfile:
```sh
make stage4
```

remove the old vagrant box if it exists and build a vagrant box from the stage4 tarfile:
```sh
make box
```

bring the cluster up provision with ansible:
```sh
vagrant up
```

this can be run all together p easily:
```sh
make stage4 box && vagrant up
```
though you probably don't want to rebuild the stage4 and create the box if just playing with ansible

# vagrant

```text
k8s-cp1  192.168.56.101
k8s-cp2  192.168.56.102
k8s-cp3  192.168.56.103
k8s-w1   192.168.56.111
k8s-w2   192.168.56.112
```

The Vagrantfile direct-boots the kernel/initramfs extracted from the generated box:

```text
vagrant/vmlinuz
vagrant/initramfs
vagrant/k8s-node-ops-stage4.box
```

The vagrant ssh user is `root`.

ssh into a node:
```sh
vagrant ssh k8s-cp1
```

download the kubeconfig:
```sh
make kubeconfig
# or
cd ansible && ansible-playbook -i inventory/vagrant.yml playbooks/save-kubeconfig.yml
```
though this will automatically happen post vagrant up provision and post vagrant destroy

# cleaning

if you just want to bring the cluster down then:
```sh
vagrant destroy -f
```

If vagrant is taking up all your storage in your root partition:
```sh
make vagrant-clean
```

to clean all artifacts and build dirs:
```sh
make clean
```

# ansible

The whole cluster is built with:

```sh
ansible-playbook -i inventory/{myInventory.yml} playbooks/k8s_setup.yml
```

For vagrant this runs automatically post `vagrant up`, so you usually don't invoke it by hand.

`playbooks/k8s_setup.yml` is split into tagged phases, so you can run a slice instead of the whole thing:

```text
node-config         containerd + kubelet on every node
keepalived          API VIP on the control plane
init                kubeadm init (run once) + join credentials
join                kubeadm join, one node at a time (serial: 1)
post-install        kubectl config, cilium CNI, control-plane/worker workloads
```

```sh
# e.g. only re-run the CNI/workload phase
ansible-playbook -i inventory/vagrant.yml playbooks/k8s_setup.yml --tags post-install
```

Notes:
- `ansible.cfg` sets `roles_path=./roles` and `collections_path=./.venv/collections`, so run from the `ansible/` dir (or use `make`).
- There is no default inventory; you must pass `-i`. The `Makefile` defaults to `INVENTORY ?= inventory/vagrant.yml`.
- Cluster-wide vars (`pod_cidr`, `service_cidr`, `cilium_version`, `metallb_pool`, etc.) live in `inventory/group_vars/k8s_nodes.yml`. Per-inventory vars like `api_vip` and `kubectl_context_name` are set in each inventory file.

# TODO

- eventually test this on real nodes in my lab with some sort of CI/CD workflow
