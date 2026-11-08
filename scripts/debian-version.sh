#!/usr/bin/env bash
# Usage: debian-version.sh SOURCE CODENAME
#
# Prints the newest version of the Debian source package SOURCE in CODENAME,
# CODENAME-updates, and CODENAME-security. Runs as root in a debian:CODENAME
# container.
set -euo pipefail

source=$1
codename=$2

"$(dirname "$0")/apt-sources.sh" "$codename"
apt-get update -qq

newest=
versions=$(apt-cache showsrc --only-source "$source" | sed -n 's/^Version: //p')
while read -r version; do
	if [ -n "$version" ] && { [ -z "$newest" ] || dpkg --compare-versions "$version" gt "$newest"; }; then
		newest=$version
	fi
done <<<"$versions"

if [ -z "$newest" ]; then
	echo "debian-version.sh: $codename has no source package $source" >&2
	exit 1
fi
echo "$newest"
