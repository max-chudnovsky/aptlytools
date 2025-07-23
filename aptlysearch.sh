#!/bin/bash
# Written by M.Chudnovsky
# tested on Debian 11 (Bullseye) with aptly 1.4.0
# This script is used to search for packages with-in aptly's snapshots.

# Make sure its ran as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

if [ $# -ne 1 ]; then
  echo "Usage: $0 <packagename or pattern>"
  echo ""
  echo "Example:"
  echo "  $0 nginx        # exact match"
  echo "  $0 nginx*       # wildcard match (prefix only)"
  echo ""
  echo "Note: Only trailing wildcards (e.g., nginx*) are supported. Patterns like *nginx or *nginx* are not allowed."
  exit 1
fi

pattern="$1"
found=0

# If pattern contains *, treat as wildcard (convert to regex), else exact match
if [[ "$pattern" == *"*"* ]]; then
  regex="^[[:space:]]*${pattern//\*/.*}[^ ]*_"
else
  regex="^[[:space:]]*${pattern}_"
fi

for snap in $(aptly snapshot list -raw); do
  match=$(aptly snapshot show -with-packages "$snap" | grep -E "$regex")
  if [ -n "$match" ]; then
    echo "$match"
    echo "Package(s) matching '$pattern' found in snapshot: $snap"
    found=1
  fi
done

if [ $found -eq 0 ]; then
  echo "No packages matching '$pattern' found in any snapshot."
  exit 1
else
  exit 0
fi