subarch: amd64
target: stage4
version_stamp: k8s
rel_type: default
profile: default/linux/amd64/23.0/systemd
source_subpath: stage3-amd64-systemd-latest.tar.xz
compression_mode: xz
decompressor_search_order: xz
snapshot_treeish: master
portage_confdir: /catalyst/portage
stage4/root_overlay: /catalyst/root_overlay
stage4/packages:
	sys-kernel/gentoo-kernel
	sys-apps/systemd
	app-containers/containerd
	sys-cluster/kubeadm
	sys-cluster/kubelet
	sys-cluster/kubectl
	net-misc/openssh
	sys-cluster/keepalived
	net-firewall/conntrack-tools
	sys-apps/ethtool
	net-misc/socat
	net-fs/nfs-utils
	dev-db/etcd
	sys-boot/grub
