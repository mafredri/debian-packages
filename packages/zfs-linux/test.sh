#!/usr/bin/env bash
# Usage: test.sh OUT
#
# Installs the zfs-linux packages build.sh wrote to OUT, runs the ICP AES-GCM
# and AES-CCM test vectors, and builds the DKMS module for the codename's
# kernel. Fails when the sse4_1 GCM implementation does not run, when a
# vector fails, when the module lacks the SSE routines, or when objtool
# reports the stack realignment the SSE routines are annotated for.
# Runs as root in the debian:CODENAME container build.sh ran in.
set -euo pipefail

out=$(cd "$1" && pwd)
export DEBIAN_FRONTEND=noninteractive

apt-get install -y -qq --no-install-recommends dkms linux-headers-amd64 xz-utils
debs=()
for name in libnvpair3linux libuutil3linux libzfs6linux libzpool6linux \
	libzfsbootenv1linux zfsutils-linux zfs-dkms python3-pyzfs zfs-test; do
	debs+=("$(find "$out" -name "${name}_*.deb")")
done
apt-get install -y -qq --no-install-recommends "${debs[@]}"

tests=/usr/share/zfs/zfs-tests
for mode in gcm ccm; do
	results=$("$tests/bin/crypto_test" -c "$tests/tests/functional/crypto/aes_${mode}_test.txt")
	echo "$results"
	if grep -E 'failed=[1-9]|^E:' <<<"$results"; then
		echo "test.sh: AES-${mode^^} test vectors failed" >&2
		exit 1
	fi
	if [ "$mode" = gcm ] && ! grep -q 'sse4_1\]: .* failed=0$' <<<"$results"; then
		echo "test.sh: the sse4_1 GCM implementation did not run" >&2
		exit 1
	fi
done

kernel=$(find /usr/src -maxdepth 1 -name 'linux-headers-*-amd64' -printf '%f\n' | sed 's/^linux-headers-//')
module=$(dpkg-query -W -f '${Version}' zfs-dkms)
module=${module%%-*}
# The zfs-dkms postinst registers the module, but aborts first without /proc.
if [ -z "$(dkms status "zfs/$module")" ]; then
	dkms add "zfs/$module"
fi
if ! dkms status -k "$kernel" "zfs/$module" | grep -qE ': (built|installed)'; then
	dkms build -k "$kernel" "zfs/$module"
fi
dkms status -k "$kernel" "zfs/$module"

log=/var/lib/dkms/zfs/$module/$kernel/x86_64/log/make.log
if grep 'unsupported stack pointer realignment' "$log"; then
	echo "test.sh: objtool rejects the SSE stack realignment; see $log" >&2
	exit 1
fi
zfs_ko=$(find "/var/lib/dkms/zfs/$module/$kernel" -name 'zfs.ko*' | head -n 1)
case $zfs_ko in
*.xz)
	xz -dc "$zfs_ko" >/tmp/zfs.ko
	zfs_ko=/tmp/zfs.ko
	;;
esac
symbols=$(nm "$zfs_ko")
count=$(grep -c ' icp_isalc_gcm_.*_sse$' <<<"$symbols" || true)
if [ "$count" -lt 24 ]; then
	echo "test.sh: zfs.ko has $count icp_isalc_gcm_*_sse symbols, expected 24" >&2
	exit 1
fi
echo "test.sh: zfs.ko for $kernel has $count SSE GCM symbols"
