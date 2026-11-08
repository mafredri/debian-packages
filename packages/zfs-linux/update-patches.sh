#!/usr/bin/env bash
# Usage: update-patches.sh
#
# Replaces patches/ with PATCH_BASE..PATCH_HEAD from PATCH_REPO, without the
# paths in PATCH_EXCLUDE, as set in package.env. Bump REVISION in package.env
# when the patches change.
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=/dev/null
. ./package.env

repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
git -C "$repo" fetch -q --depth=100 "$PATCH_REPO" \
	"refs/heads/$PATCH_BASE:refs/base" "refs/heads/$PATCH_HEAD:refs/head"
if ! git -C "$repo" merge-base --is-ancestor refs/base refs/head; then
	echo "update-patches.sh: $PATCH_HEAD is not based on $PATCH_BASE within 100 commits" >&2
	exit 1
fi

exclude=()
for path in ${PATCH_EXCLUDE:-}; do
	exclude+=(":(exclude)$path")
done
rm -f patches/*.patch patches/series
git -C "$repo" -c core.abbrev=12 format-patch -q --no-signature --zero-commit \
	-o "$PWD/patches" refs/base..refs/head -- . "${exclude[@]}"
(cd patches && ls -- *.patch >series)
cat patches/series
