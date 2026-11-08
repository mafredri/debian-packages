#!/usr/bin/env bash
# Usage: apt-sources.sh CODENAME
#
# Replaces the apt sources of a debian:CODENAME container with the main and
# contrib binary and source packages of CODENAME, CODENAME-updates, and
# CODENAME-security.
set -euo pipefail

codename=$1

rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: $codename $codename-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.debian.org/debian-security
Suites: $codename-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
