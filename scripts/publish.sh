#!/usr/bin/env bash
# Usage: publish.sh SITE
#
# Writes the apt repository to SITE: for each package and codename, the
# binary packages of the release with the newest version, a Packages index
# and a signed Release per codename, and the public signing key as key.asc.
# APT_SIGNING_KEY holds the armored private key. Needs gh with GH_TOKEN,
# dpkg, apt-ftparchive, and gpg.
set -euo pipefail

site=$1
root=$(cd "$(dirname "$0")/.." && pwd)
: "${APT_SIGNING_KEY:?APT_SIGNING_KEY must hold the armored private signing key}"

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
gpg --batch --quiet --import <<<"$APT_SIGNING_KEY"
fingerprint=$(gpg --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')

mkdir -p "$site"
gpg --armor --export "$fingerprint" >"$site/key.asc"

tags=$(gh release list --limit 1000 --json tagName --jq '.[].tagName')
published=()
for env in "$root"/packages/*/package.env; do
	unset SOURCE CODENAMES
	# shellcheck source=/dev/null
	. "$env"
	for codename in $CODENAMES; do
		newest=
		newest_version=
		while read -r tag; do
			if [ -z "$tag" ]; then
				continue
			fi
			version=$(gh release view "$tag" --json name --jq .name)
			if [ -z "$newest" ] || dpkg --compare-versions "$version" gt "$newest_version"; then
				newest=$tag
				newest_version=$version
			fi
		done <<<"$(grep "^$codename/$SOURCE/" <<<"$tags" || true)"
		if [ -z "$newest" ]; then
			echo "publish.sh: no release for $SOURCE in $codename yet" >&2
			continue
		fi
		echo "publish.sh: $codename $SOURCE $newest_version"
		gh release download "$newest" --dir "$site/pool/$codename/$SOURCE" --pattern '*.deb'
		published+=("$codename")
	done
done

for codename in $(printf '%s\n' "${published[@]}" | sort -u); do
	dist=$site/dists/$codename
	mkdir -p "$dist/main/binary-amd64"
	(cd "$site" && apt-ftparchive packages "pool/$codename") >"$dist/main/binary-amd64/Packages"
	gzip -9kn "$dist/main/binary-amd64/Packages"
	xz -k "$dist/main/binary-amd64/Packages"
	(cd "$dist" && apt-ftparchive \
		-o APT::FTPArchive::Release::Origin=mafredri \
		-o APT::FTPArchive::Release::Label=debian-packages \
		-o APT::FTPArchive::Release::Suite="$codename" \
		-o APT::FTPArchive::Release::Codename="$codename" \
		-o APT::FTPArchive::Release::Architectures=amd64 \
		-o APT::FTPArchive::Release::Components=main \
		release .) >"$site/Release.tmp"
	mv "$site/Release.tmp" "$dist/Release"
	gpg --batch --yes --local-user "$fingerprint" --clearsign \
		--output "$dist/InRelease" "$dist/Release"
	gpg --batch --yes --local-user "$fingerprint" --armor --detach-sign \
		--output "$dist/Release.gpg" "$dist/Release"
done
