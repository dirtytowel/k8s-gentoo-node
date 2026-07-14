subarch: amd64
target: stage4
version_stamp: k8s
rel_type: default
profile: default/linux/amd64/23.0/systemd
source_subpath: stage3-amd64-systemd
compression_mode: xz
decompressor_search_order: xz
update_seed: yes
portage_confdir: /home/ethan/dat/repos/gentoo-k8s/catalyst/portage
root_overlay: /home/ethan/dat/repos/gentoo-k8s/catalyst/root_overlay
packages:
	sys-kernel/gentoo-kernel
	sys-apps/systemd
	app-containers/containerd
	sys-cluster/kubeadm
	sys-cluster/kubelet
	sys-cluster/kubectl
	net-misc/openssh
	net-misc/keepalived
	net-fs/nfs-utils
	sys-apps/etcd-utils
	sys-boot/grub
boot/kernel: gentoo-kernel
