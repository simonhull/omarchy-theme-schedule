#!/bin/bash

# Runs every test file and exits non-zero if any of them failed.

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

status=0
for file in *-test.sh; do
  bash "$file" || status=1
done
exit $status
