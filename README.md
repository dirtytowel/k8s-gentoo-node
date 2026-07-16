# k8s-node-ops

Just a set of scripts/playbooks to build a gentoo based kubernetes node image, keep it updated, keep things CI/CD and IaC, wrap it in a vagrant/libvirt box, and boot a tiny 3 node control plane lab so I can test the playbooks/scripts ansible without touching real machines.

# how it works

The rough dev workflow is:

`CATALYST_STAGE4 -> VAGRANT_BOX -> LIBVIRT_VMS -> ANSIBLE`

CATALYST_STAGE4: gentoo stage4 tarball with kubernetes/containerd/keepalived/etc already installed

VAGRANT_BOX: qcow2 rootfs made from the stage4 tarball, plus the bare minimum vagrant needs to ssh in

LIBVIRT_VMS: 3 control plane nodes using the same box image

ANSIBLE: eventually configures the actual distributed control plane.

# layout

```text
catalyst/                 gentoo catalyst config for building the stage4
ansible/playbooks/         local box build playbook
ansible/inventory/         vagrant and real-host inventory
ansible/group_vars/        cluster variables
vagrant/                   generated box/kernel/initramfs/build junk
Vagrantfile                3 node libvirt lab
Makefile                   lazy entrypoints because typing is for interns
```

# dependencies

On the host you need roughly:

```sh
docker compose
vagrant
vagrant-libvirt
libvirt
qemu-img
ansible
mkfs.ext4
tar
virsh
```

The box build still uses root because it loop mounts an ext4 image. yes that sucks. rootless image building is probably doable with `fakeroot`/`mke2fs -d` later, but right now I want the cluster to boot more than I want ideological purity.

# how to build

Build the gentoo stage4:

```sh
make stage4
```

Build the vagrant box from that stage4:

```sh
make box
```

This also tries to clean the stale vagrant/libvirt box cache, because vagrant-libvirt likes to keep old qcow2 base images around like a hoarder with a Ruby interpreter.

Bring up the lab:

```sh
make vagrant
```

or just:

```sh
vagrant up
```

# vagrant nodes

```text
k8s-cp1  192.168.56.101
k8s-cp2  192.168.56.102
k8s-cp3  192.168.56.103
```

The Vagrantfile direct-boots the kernel/initramfs extracted from the generated box:

```text
vagrant/vmlinuz
vagrant/initramfs
vagrant/k8s-node-ops-stage4.box
```

The guest ssh user is `root`. sudo is not installed in the image because root already means root, shocking concept.

# cleaning the cache

If vagrant keeps booting stale garbage:

```sh
make clean-box
```

That runs:

```sh
vagrant destroy -f
vagrant box remove k8s-node-ops-stage4 --all --force
make clean-box-cache
```

`clean-box-cache` removes matching libvirt base volumes from the default pool:

```sh
virsh -c qemu:///system vol-list default | awk '/k8s-node-ops-stage4_vagrant_box_image_/ {print $1}' | xargs -r -I{} virsh -c qemu:///system vol-delete {} --pool default
```

# using the nodes

ssh into a node:

```sh
vagrant ssh k8s-cp1
```

sync portage inside the guest:

```sh
emerge --sync
```

then update if you like:

```sh
emerge -auDU @world
```

The image writes `/etc/portage/repos.conf/gentoo.conf` and links `/etc/resolv.conf` to systemd-resolved so DNS and portage sync work after DHCP comes up.

# ansible

Current inventory files:

```text
ansible/inventory/vagrant.yml   local libvirt lab
ansible/inventory/hosts.yml     real machines
```

Cluster vars live here:

```text
ansible/group_vars/k8s_nodes.yml
```

The intended control plane setup is:

```text
containerd -> keepalived VIP -> kubeadm init -> kubeadm join -> calico
```

That distributed control plane playbook is not done yet. the whole point of this repo is getting to a repeatable base image so that part can be worked on without bare metal roulette.

# TODO

- make the box build rootless with fakeroot or mke2fs -d
- finish ansible roles for containerd, keepalived, kubeadm, and calico
- maybe make vagrant provisioning call ansible automatically once it isn't fucking broken
- eventually test this on real nodes in my lab with some sort of CI/CD workflow
