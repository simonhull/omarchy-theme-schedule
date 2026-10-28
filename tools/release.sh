#!/bin/bash

# Cuts a release: tools/release.sh <version>, or make release VERSION=<version>.
#
# install.sh reads the PKGBUILD from main, so main must never carry a version
# whose checksum is not yet pinned. The order is therefore:
#
#   1. bump the version, test, commit "Release vX.Y.Z", tag it
#   2. push only the tag; GitHub builds the source tarball from it
#   3. download that tarball twice and require the same checksum
#   4. pin the checksum, commit it, and only then push main
#
# Environment:
#   RELEASE_REMOTE        remote to push to (default: origin)
#   RELEASE_TARBALL_URL   tarball URL with %s for the version
#                         (default: the GitHub tag archive)
#   RELEASE_TEST_COMMAND  what proves the tree is releasable (default: make test)
#   RELEASE_ATTEMPTS      tries per download while GitHub catches up (default: 10)
#   RELEASE_RETRY_DELAY   seconds between tries (default: 3)

set -euo pipefail

REMOTE=${RELEASE_REMOTE:-origin}
URL_TEMPLATE=${RELEASE_TARBALL_URL:-https://github.com/simonhull/omarchy-theme-schedule/archive/refs/tags/v%s.tar.gz}
TEST_COMMAND=${RELEASE_TEST_COMMAND:-make test}
ATTEMPTS=${RELEASE_ATTEMPTS:-10}
DELAY=${RELEASE_RETRY_DELAY:-3}

die() {
  echo "release: $*" >&2
  exit 1
}

# Prints the sha256 of the tarball at a URL, retrying while it is not there.
tarball_sum() {
  local url=$1 attempt sum
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if sum=$(curl -fsSL "$url" | sha256sum); then
      echo "${sum%% *}"
      return 0
    fi
    echo "release: $url not available yet (try $attempt of $ATTEMPTS)" >&2
    ((attempt < ATTEMPTS)) && sleep "$DELAY"
  done
  return 1
}

main() {
  local version tag url sum_a sum_b

  [[ ${1:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Usage: tools/release.sh <version>, such as 0.2.0"
  version=$1
  tag=v$version

  cd -- "$(git rev-parse --show-toplevel)"

  [[ -z $(git status --porcelain) ]] || die "the working tree is not clean"
  [[ $(git branch --show-current) == main ]] || die "release from main, not $(git branch --show-current)"
  git fetch --quiet "$REMOTE" main
  [[ $(git rev-parse HEAD) == "$(git rev-parse FETCH_HEAD)" ]] ||
    die "main is not up to date with $REMOTE/main"
  if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null ||
    [[ -n $(git ls-remote --tags "$REMOTE" "refs/tags/$tag") ]]; then
    die "the tag $tag already exists"
  fi

  sed -i -e "s/^pkgver=.*/pkgver=$version/" -e 's/^pkgrel=.*/pkgrel=1/' PKGBUILD
  sed -i "s/^TS_VERSION=.*/TS_VERSION=$version/" bin/omarchy-theme-schedule

  # An unreleasable tree is put back as it was, not left half edited.
  if ! bash -c "$TEST_COMMAND"; then
    git checkout --quiet -- .
    die "the tests failed; nothing was committed"
  fi

  git commit --quiet -am "Release $tag"
  git tag -a "$tag" -m "$tag"

  echo "==> Pushing $tag"
  git push --quiet "$REMOTE" "refs/tags/$tag"

  # shellcheck disable=SC2059 # the template is the format string, by design
  url=$(printf "$URL_TEMPLATE" "$version")
  echo "==> Downloading $url twice"
  sum_a=$(tarball_sum "$url") || die "could not download $url; $tag is pushed but main is not"
  sum_b=$(tarball_sum "$url") || die "could not download $url again; $tag is pushed but main is not"
  [[ $sum_a == "$sum_b" ]] || die "two downloads of $url differ ($sum_a, $sum_b); $tag is pushed but main is not"

  sed -i "s/^sha256sums=.*/sha256sums=('$sum_a')/" PKGBUILD
  git commit --quiet -am "Pin the $tag source checksum"

  echo "==> Pushing main"
  git push --quiet "$REMOTE" main
  echo "==> Released $tag, sha256 $sum_a"
}

main "$@"
