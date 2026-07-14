# Catalyst phase 1

Defaults: amd64, systemd profile, `stage3-amd64-systemd` seed, Cilium pod CIDR later set to `172.16.0.0/12` unless you stop being vague.

Build:

```sh
catalyst -f catalyst/specs/stage4-k8s.spec
```

Put the seed stage3 where your Catalyst install expects it, usually `/var/tmp/catalyst/builds/default/stage3-amd64-systemd-latest.tar.xz`, or adjust `source_subpath` in the spec.
