#!/usr/bin/env bash
# Usage: plan.sh EVENT [BASE HEAD]
#
# Prints the package builds to run as a JSON array of objects with package,
# codename, version, and tag. For each packages/<name>/package.env and each
# of its CODENAMES, version is Debian's newest source version followed by
# +<SUFFIX><REVISION>, and tag is <codename>/<SOURCE>/<version> with ":" and
# "~", which Git refs reject, replaced by "_".
#
# When EVENT is pull_request, the builds are the packages whose directory
# changed between BASE and HEAD, or every package when scripts/ or the
# Packages workflow changed. A changed package whose release already exists
# fails, because its REVISION needs a bump. For other events, the builds are
# the ones whose release does not exist yet.
#
# Needs docker, jq, and gh with GH_TOKEN.
set -euo pipefail

event=$1
base=${2:-}
head=${3:-HEAD}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

changed=
if [ "$event" = pull_request ]; then
	changed=$(git diff --name-only "$base...$head")
fi
shared=false
if grep -qE '^(scripts/|\.github/workflows/packages\.yaml$)' <<<"$changed"; then
	shared=true
fi

load_env() {
	unset SOURCE CODENAMES UPSTREAM_VERSION SUFFIX REVISION
	# shellcheck source=/dev/null
	. "$1"
}

release_exists() {
	local out
	if out=$(gh release view "$1" --json tagName 2>&1); then
		return 0
	fi
	if grep -q 'release not found' <<<"$out"; then
		return 1
	fi
	echo "plan.sh: gh release view $1: $out" >&2
	exit 1
}

builds=()
for env in packages/*/package.env; do
	package=$(basename "$(dirname "$env")")
	load_env "$env"

	package_changed=false
	if grep "^packages/$package/" <<<"$changed" | grep -qv '\.md$'; then
		package_changed=true
	fi
	if [ "$event" = pull_request ] && ! $package_changed && ! $shared; then
		continue
	fi

	for codename in $CODENAMES; do
		debian=$(docker run --rm -v "$root/scripts:/scripts:ro" "debian:$codename" \
			/scripts/debian-version.sh "$SOURCE" "$codename")
		upstream=${debian#*:}
		upstream=${upstream%-*}
		if [ "$upstream" != "$UPSTREAM_VERSION" ]; then
			echo "plan.sh: Debian $codename has $SOURCE $debian, but the $package patches target $UPSTREAM_VERSION. Rebase the patches onto $upstream and update UPSTREAM_VERSION in $env." >&2
			exit 1
		fi

		version=$debian+$SUFFIX$REVISION
		tag=$codename/$SOURCE/$(tr ':~' '__' <<<"$version")
		if release_exists "$tag"; then
			if [ "$event" != pull_request ]; then
				continue
			fi
			if $package_changed; then
				echo "plan.sh: release $tag already exists. Bump REVISION in $env." >&2
				exit 1
			fi
		fi
		builds+=("$(jq -cn --arg package "$package" --arg codename "$codename" \
			--arg version "$version" --arg tag "$tag" '$ARGS.named')")
	done
done

if [ ${#builds[@]} -eq 0 ]; then
	echo '[]'
else
	printf '%s\n' "${builds[@]}" | jq -cs .
fi
