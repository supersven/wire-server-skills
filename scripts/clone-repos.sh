#!/usr/bin/env bash
# Shallow-clone (or update) repos used to discover issues for skill rules into ./tmp.
set -euo pipefail

for repo in wireapp/wire-server wireapp/ldap-scim-bridge; do
  dir=tmp/${repo#*/}
  if [ -d "$dir" ]; then
    git -C "$dir" pull --ff-only
  else
    git clone --depth 1 "https://github.com/$repo" "$dir"
  fi
done
