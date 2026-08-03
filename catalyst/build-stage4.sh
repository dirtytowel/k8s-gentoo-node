#!/bin/sh
set -eu

mirror=https://distfiles.gentoo.org/releases/amd64/autobuilds
stage3=/var/tmp/catalyst/builds/stage3-amd64-systemd-latest.tar.xz
repo=/var/tmp/catalyst/repos/gentoo.git
spec=/catalyst/specs/stage4-k8s.spec

mkdir -p /var/tmp/catalyst/builds /var/tmp/catalyst/repos /var/tmp/catalyst/snapshots

echo 'finding latest stage3'
path=$(wget -qO- "$mirror/latest-stage3-amd64-systemd.txt" | grep -E '^[0-9]{8}T[0-9]{6}Z/stage3-amd64-systemd-[^[:space:]]+\.tar\.xz[[:space:]]' | cut -d' ' -f1)
[ -n "$path" ]
echo "downloading $path"
wget -O /var/tmp/catalyst/builds/stage3-amd64-systemd-latest.tar.xz "$mirror/$path"

if [ -d "$repo" ]; then
	echo 'updating gentoo repo'
	git -C "$repo" fetch --depth=1 origin +master:refs/heads/master
else
	echo 'cloning gentoo repo'
	git clone --bare --depth=1 https://anongit.gentoo.org/git/repo/gentoo.git "$repo"
fi

# in order for snapshots to really work I would need to mount artifacts in some way with object storage or something
echo 'creating gentoo snapshot'
catalyst -s master

echo 'building stage4'
catalyst -f "$spec"
