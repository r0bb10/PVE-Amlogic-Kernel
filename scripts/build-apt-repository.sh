#!/usr/bin/env bash
set -euo pipefail

scan_dir="${SCAN_DIR:?SCAN_DIR is required}"
signing_key="${SIGNING_KEY:?SIGNING_KEY is required}"
repo_name="${REPOSITORY_NAME:-pve-kernel}"
codename="${CODENAME:-trixie}"
component="${COMPONENT:-main}"
architecture="${ARCHITECTURE:-arm64}"
work_dir="$(mktemp -d)"
repo_dir="$work_dir/repository"

gpg --batch --import <<<"$signing_key"
fingerprint="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
test -n "$fingerprint"

mkdir -p "$repo_dir/conf"
cat > "$repo_dir/conf/distributions" <<EOF
Origin: $repo_name
Label: $repo_name
Suite: $codename
Codename: $codename
Components: $component
Architectures: $architecture
SignWith: $fingerprint
EOF

gpg --batch --armor --export "$fingerprint" > "$repo_dir/gpg.key"
reprepro -b "$repo_dir" -C "$component" includedeb "$codename" "$scan_dir"/*.deb
chmod -R a+rX "$repo_dir"

printf 'dir=%s\n' "$repo_dir" >> "$GITHUB_OUTPUT"
