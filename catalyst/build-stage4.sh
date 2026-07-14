#!/bin/sh
set -eu

mirror=https://distfiles.gentoo.org/releases/amd64/autobuilds
stage3=/var/tmp/catalyst/builds/stage3-amd64-systemd-latest.tar.xz
repo=/var/tmp/catalyst/repos/gentoo.git
spec=/catalyst/specs/stage4-k8s.spec

log(){ printf '>>> %s\n' "$*"; }

fetch_stage3(){
	[ -s "$stage3" ] && { log "stage3 exists: $stage3"; return; }
	log 'finding latest stage3'
	path=$(wget -qO- "$mirror/latest-stage3-amd64-systemd.txt" | grep -E '^[0-9]{8}T[0-9]{6}Z/stage3-amd64-systemd-[^[:space:]]+\.tar\.xz[[:space:]]' | cut -d' ' -f1)
	[ -n "$path" ]
	log "downloading $path"
	wget -O "$stage3" "$mirror/$path"
}

sync_repo(){
	if [ -d "$repo" ]; then
		log 'updating gentoo repo'
		git -C "$repo" fetch --depth=1 origin master:refs/heads/master
	else
		log 'cloning gentoo repo'
		git clone --bare --depth=1 https://anongit.gentoo.org/git/repo/gentoo.git "$repo"
	fi
	log 'creating gentoo snapshot'
	catalyst -s master
}

build_stage4(){
	flags=
	[ "${CATALYST_CLEAN:-}" = 1 ] && flags=-a
	log 'building stage4'
	catalyst $flags -f "$spec"
}

mkdir -p /var/tmp/catalyst/builds /var/tmp/catalyst/repos /var/tmp/catalyst/snapshots
fetch_stage3
sync_repo
build_stage4
