#!/usr/bin/env bash
# Usage: build.sh PACKAGE CODENAME VERSION OUT
#
# Rebuilds the Debian source package of packages/PACKAGE with its patches
# appended to Debian's quilt series, and copies the binary packages (without
# debug symbols), .buildinfo, and .changes to OUT. VERSION is the version
# plan.sh printed; the build fetches the Debian version it starts with.
# Runs as root in a debian:CODENAME container.
set -euo pipefail

package=$1
codename=$2
version=$3
out=$4
mkdir -p "$out"
out=$(cd "$out" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)
package_dir=$root/packages/$package
# shellcheck source=/dev/null
. "$package_dir/package.env"

debian=${version%"+$SUFFIX$REVISION"}
if [ "$debian" = "$version" ]; then
	echo "build.sh: version $version does not end in +$SUFFIX$REVISION" >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
"$root/scripts/apt-sources.sh" "$codename"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	build-essential ca-certificates devscripts dpkg-dev fakeroot quilt
apt-get build-dep -y -qq "$SOURCE=$debian"

work=$(mktemp -d)
cd "$work"
apt-get source -qq "$SOURCE=$debian"
cd "$SOURCE"-*/

# Debian's patches are applied when the source is unpacked; quilt applies
# the ones appended here and fails if one does not apply.
mkdir -p debian/patches/debian-packages
while read -r patch; do
	cp "$package_dir/patches/$patch" debian/patches/debian-packages/
	echo "debian-packages/$patch" >>debian/patches/series
done <"$package_dir/patches/series"
QUILT_PATCHES=debian/patches quilt push -a

DEBFULLNAME="Mathias Fredriksson" DEBEMAIL="mafredri@gmail.com" \
	dch --newversion "$version" --distribution "$codename" \
	--force-distribution "$CHANGELOG"

DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck" dpkg-buildpackage -b -uc -us

find .. -maxdepth 1 -type f \( -name '*.deb' ! -name '*-dbgsym_*' \
	-o -name '*.buildinfo' -o -name '*.changes' \) -exec cp -t "$out" {} +
ls -l "$out"
