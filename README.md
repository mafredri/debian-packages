# Debian packages

My personal Debian packages: Debian's own source packages, rebuilt with
patches, served as a signed apt repository from GitHub Pages.

## Packages

- `zfs-linux` (trixie): Debian's ZFS with SSE4.1 AES-GCM acceleration, for
  CPUs that have AES-NI and PCLMULQDQ but not AVX. The patches come from
  [mafredri/zfs#1](https://github.com/mafredri/zfs/pull/1).

## Host setup

Install the signing key and check that its fingerprint matches the one
below:

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://mafredri.github.io/debian-packages/key.asc |
	sudo tee /etc/apt/keyrings/mafredri-debian-packages.asc >/dev/null
gpg --show-keys /etc/apt/keyrings/mafredri-debian-packages.asc
```

Fingerprint: not created yet.

Add the repository, and pin it so its packages replace Debian's packages of
the same name:

```sh
sudo tee /etc/apt/sources.list.d/mafredri-debian-packages.sources >/dev/null <<'EOF'
Types: deb
URIs: https://mafredri.github.io/debian-packages
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/mafredri-debian-packages.asc
EOF
sudo tee /etc/apt/preferences.d/mafredri-debian-packages >/dev/null <<'EOF'
Package: *
Pin: origin mafredri.github.io
Pin-Priority: 1001
EOF
sudo apt update
```

Priority 1001 keeps these packages installed when Debian publishes a newer
version, until the next rebuild here. A security fix in a Debian package
reaches the host after that rebuild, normally within a day.

### zfs-linux

`apt upgrade` installs the rebuilt packages, and DKMS builds the module for
each installed kernel that has its headers installed. After a reboot, or a
module reload, the GCM implementation list includes `sse4_1` on a CPU that
supports it:

```sh
cat /sys/module/icp/parameters/icp_gcm_impl
```

With `fastest`, the default, the module uses `avx` when the CPU has AVX, and
`sse4_1` when it has SSE4.1, AES-NI, and PCLMULQDQ but no AVX. The encrypted
data on disk is the same either way.

To go back to Debian's packages, delete the two files above, run
`sudo apt update`, and install Debian's version of each installed ZFS
package with `sudo apt install --allow-downgrades <package>=<version>`,
taking the versions from `apt policy <package>`.

## How packages are built

`.github/workflows/packages.yaml` runs on pull requests, on pushes to
`main`, and daily. For each `packages/<name>/package.env` and Debian
codename, `scripts/plan.sh` looks up Debian's newest source version and
appends `+<SUFFIX><REVISION>`. When no release has that version yet,
`scripts/build.sh` rebuilds the source package in a `debian:<codename>`
container with `packages/<name>/patches/` appended to Debian's quilt
series, and `packages/<name>/test.sh` tests the result. The workflow then
creates the release `<codename>/<source>/<version>` with the binary
packages, and `scripts/publish.sh` deploys the newest release of each
package to Pages, signed with the `APT_SIGNING_KEY` secret.

Pull requests build and test the packages they change, without releasing
or publishing. A pull request that changes a package with an existing
release fails until it bumps `REVISION`.

The build fails when Debian moves a package to an upstream version other
than `UPSTREAM_VERSION`. Rebase the patches onto the new version, update
them with `mise run patches/update <name>`, and update `UPSTREAM_VERSION`.

GitHub disables the daily schedule in a public repository after 60 days
without activity; merging Renovate's pull requests keeps it running.

## Local checks

[mise](https://mise.jdx.dev) installs the tools in `mise.toml` and runs the
checks:

```sh
mise run ci
```

Build and test a package with Docker:

```sh
mise run build zfs-linux trixie
```
