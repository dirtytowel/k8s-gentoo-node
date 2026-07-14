#!/bin/sh
set -eu
base=https://distfiles.gentoo.org/releases/amd64/autobuilds
dst=/var/tmp/catalyst/builds/stage3-amd64-systemd-latest.tar.xz
mkdir -p /var/tmp/catalyst/builds/default /var/tmp/catalyst/builds /var/tmp/catalyst/snapshots
[ -s "$dst" ] || [ ! -s /var/tmp/catalyst/builds/default/stage3-amd64-systemd-latest.tar.xz ] || cp /var/tmp/catalyst/builds/default/stage3-amd64-systemd-latest.tar.xz "$dst"
mkdir -p /var/tmp/catalyst/repos
if [ -d /var/tmp/catalyst/repos/gentoo.git ]; then git -C /var/tmp/catalyst/repos/gentoo.git fetch --depth=1 origin master:refs/heads/master; else git clone --bare --depth=1 https://anongit.gentoo.org/git/repo/gentoo.git /var/tmp/catalyst/repos/gentoo.git; fi
if [ ! -s "$dst" ]; then python3 - "$base" "$dst" <<'PY'
import re,sys,urllib.request
base,dst=sys.argv[1:]
idx=urllib.request.urlopen(base+'/latest-stage3-amd64-systemd.txt').read().decode()
p=next(l.split()[0] for l in idx.splitlines() if re.match(r'^\d{8}T\d{6}Z/stage3-amd64-systemd-.*\.tar\.xz\s',l))
urllib.request.urlretrieve(base+'/'+p,dst)
PY
fi
catalyst -s master
catalyst -a -f /catalyst/specs/stage4-k8s.spec
