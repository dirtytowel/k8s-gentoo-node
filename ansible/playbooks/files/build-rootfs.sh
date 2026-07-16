#!/bin/sh
set -eu

if [ "${1:-}" != --inside ]; then
	exec unshare --user --map-auto --map-root-user "$0" --inside "$@"
fi

shift
stage4=$1
build_dir=$2
disk_gb=$3
artifact_dir=$4
rootfs=$build_dir/rootfs
overlay=$build_dir/overlay
raw=$build_dir/root.img

rm -rf "$rootfs"
mkdir -p "$rootfs"
trap 'rm -rf "$rootfs"' EXIT

tar --xattrs --xattrs-include='*.*' --numeric-owner --exclude='./dev/console' --exclude='./dev/null' -xpf "$stage4" -C "$rootfs"
cp -a "$overlay"/. "$rootfs"/

set -- "$rootfs"/boot/kernel-*
cp "$1" "$artifact_dir/vmlinuz"
set -- "$rootfs"/boot/initramfs-*.img
cp "$1" "$artifact_dir/initramfs"

truncate -s "${disk_gb}G" "$raw"
mke2fs -q -F -t ext4 -d "$rootfs" "$raw"
