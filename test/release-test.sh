# shellcheck shell=bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# tools/release.sh runs in a throwaway clone whose only remote is a local bare
# repo, so the real origin is never contacted. A post-receive hook in the bare
# repo and a fake curl both write to one events file, recording what the
# remote's main says at each step; that is how the push order is proved.

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid

main_version_in() {
  git --git-dir="$1" show refs/heads/main:PKGBUILD | sed -n 's/^pkgver=//p'
}

given_remote_and_clone() {
  BARE="$TEST_ROOT/remote.git"
  WORK="$TEST_ROOT/work"
  EVENTS="$TEST_ROOT/events"
  : >"$EVENTS"
  git init -q --bare -b main "$BARE"
  git clone -q "$BARE" "$WORK" 2>/dev/null
  (
    cd "$WORK" || exit 1
    git switch -q -c main
    mkdir -p bin tools
    printf 'pkgname=demo\npkgver=0.1.0\npkgrel=3\nsha256sums=('"'"'0000'"'"')\n' >PKGBUILD
    printf '#!/bin/bash\nTS_VERSION=0.1.0\n' >bin/omarchy-theme-schedule
    cp "$REPO/tools/release.sh" tools/release.sh 2>/dev/null || :
    git add -A
    git commit -q -m "Start"
    git push -q origin main
  )
  # Hooks go in after the first push, so only the release's pushes are logged.
  cat >"$BARE/hooks/post-receive" <<HOOK
#!/bin/bash
while read -r old new ref; do
  echo "push \${ref#refs/} main=\$(git show refs/heads/main:PKGBUILD | sed -n 's/^pkgver=//p')" >>"$EVENTS"
done
HOOK
  chmod +x "$BARE/hooks/post-receive"

  # The fake fetcher: a tag that is not on the remote yet is a 404 the first
  # time, then GitHub catches up. It serves git archive of the tag.
  stub curl 'url=${*: -1}
ver=${url##*/v}
ver=${ver%.tar.gz}
count=$(( $(cat "$TEST_ROOT/curl-count" 2>/dev/null || echo 0) + 1 ))
echo "$count" >"$TEST_ROOT/curl-count"
if (( count == 1 )); then
  echo "fetch $url -> 404" >>"'"$EVENTS"'"
  exit 22
fi
echo "fetch $url main=$(git --git-dir="'"$BARE"'" show refs/heads/main:PKGBUILD | sed -n "s/^pkgver=//p")" >>"'"$EVENTS"'"
git --git-dir="'"$BARE"'" archive --format=tar.gz --prefix="demo-$ver/" "v$ver"'
  export TEST_ROOT
  export RELEASE_REMOTE=upstream
  export RELEASE_TARBALL_URL='https://example.invalid/archive/v%s.tar.gz'
  export RELEASE_TEST_COMMAND=true
  export RELEASE_RETRY_DELAY=0
  git -C "$WORK" remote rename origin upstream
}

release() {
  (cd "$WORK" && bash tools/release.sh "$@" 2>&1)
}

bare_refs() {
  git --git-dir="$BARE" for-each-ref --format='%(refname) %(objectname)'
}

test_release_pushes_the_tag_before_main_and_pins_the_checksum() {
  given_remote_and_clone
  local out expected
  out=$(release 0.2.0)
  assert_eq 0 "$?" "release succeeds"

  # The tag is on the remote while main still says 0.1.0; the pin and main
  # arrive together, last.
  assert_eq "$(cat <<'EOT'
push tags/v0.2.0 main=0.1.0
fetch https://example.invalid/archive/v0.2.0.tar.gz -> 404
fetch https://example.invalid/archive/v0.2.0.tar.gz main=0.1.0
fetch https://example.invalid/archive/v0.2.0.tar.gz main=0.1.0
push heads/main main=0.2.0
EOT
)" "$(cat "$EVENTS")" "order of events at the remote"

  expected=$(git --git-dir="$BARE" archive --format=tar.gz --prefix=demo-0.2.0/ v0.2.0 | sha256sum | cut -d' ' -f1)
  assert_eq 0.2.0 "$(main_version_in "$BARE")" "remote main has the new version"
  assert_eq "sha256sums=('$expected')" "$(git --git-dir="$BARE" show refs/heads/main:PKGBUILD | grep '^sha256sums=')" "remote main has the checksum"
  assert_eq "pkgrel=1" "$(git --git-dir="$BARE" show refs/heads/main:PKGBUILD | grep '^pkgrel=')" "pkgrel reset"
  assert_eq "TS_VERSION=0.2.0" "$(git --git-dir="$BARE" show refs/heads/main:bin/omarchy-theme-schedule | grep '^TS_VERSION=')" "bin version"
  assert_eq "Pin the v0.2.0 source checksum"$'\n'"Release v0.2.0" "$(git --git-dir="$BARE" log -2 --format=%s main)" "commit messages"
  assert_eq tag "$(git --git-dir="$BARE" cat-file -t refs/tags/v0.2.0)" "annotated tag"
  assert_eq "$(git --git-dir="$BARE" rev-parse main~1)" "$(git --git-dir="$BARE" rev-parse 'v0.2.0^{commit}')" "tag is on the release commit"
  assert_eq "$(git -C "$WORK" rev-parse main)" "$(git --git-dir="$BARE" rev-parse main)" "local and remote main agree"
  assert_eq "" "$(git -C "$WORK" status --porcelain)" "tree clean"
}

refuses() {
  local message=$1 expected_text=$2 before out status
  shift 2
  before=$(bare_refs)
  out=$(release "$@")
  status=$?
  assert_eq 1 "$status" "$message: exits 1"
  assert_contains "$out" "$expected_text" "$message: says why"
  assert_eq "$before" "$(bare_refs)" "$message: remote untouched"
  assert_eq "" "$(cat "$EVENTS")" "$message: nothing pushed or fetched"
}

test_refuses_without_a_proper_version() {
  given_remote_and_clone
  refuses "no version" "Usage"
  refuses "bad version" "Usage" v1.0
}

test_refuses_a_dirty_tree() {
  given_remote_and_clone
  echo x >"$WORK/stray"
  refuses "untracked file" "not clean" 0.2.0
  rm "$WORK/stray"
  echo x >>"$WORK/PKGBUILD"
  refuses "modified file" "not clean" 0.2.0
}

test_refuses_off_main() {
  given_remote_and_clone
  git -C "$WORK" switch -q -c other
  refuses "other branch" "main" 0.2.0
}

test_refuses_when_behind_the_remote() {
  given_remote_and_clone
  git clone -q "$BARE" "$TEST_ROOT/other" 2>/dev/null
  git -C "$TEST_ROOT/other" commit -q --allow-empty -m "Elsewhere"
  git -C "$TEST_ROOT/other" push -q origin main
  : >"$EVENTS"
  refuses "behind" "up to date" 0.2.0
}

test_refuses_when_ahead_of_the_remote() {
  given_remote_and_clone
  git -C "$WORK" commit -q --allow-empty -m "Unpushed"
  refuses "ahead" "up to date" 0.2.0
}

test_refuses_when_the_tag_exists() {
  given_remote_and_clone
  git -C "$WORK" tag v0.2.0
  refuses "local tag" "already exists" 0.2.0
  git -C "$WORK" tag -d v0.2.0 >/dev/null
  git -C "$WORK" tag v0.3.0
  git -C "$WORK" push -q upstream v0.3.0
  git -C "$WORK" tag -d v0.3.0 >/dev/null
  : >"$EVENTS"
  refuses "tag only on the remote" "already exists" 0.3.0
}

test_a_failing_test_run_stops_before_anything_is_committed() {
  given_remote_and_clone
  local head
  head=$(git -C "$WORK" rev-parse HEAD)
  export RELEASE_TEST_COMMAND=false
  refuses "failing tests" "tests failed" 0.2.0
  assert_eq "$head" "$(git -C "$WORK" rev-parse HEAD)" "no commit"
  assert_eq "" "$(git -C "$WORK" status --porcelain)" "edits put back"
  assert_eq "" "$(git -C "$WORK" tag)" "no tag"
}

test_mismatched_downloads_leave_main_alone() {
  given_remote_and_clone
  stub curl 'echo "$RANDOM"'
  local out
  out=$(release 0.2.0)
  assert_eq 1 "$?" "fails"
  assert_contains "$out" "differ" "explains"
  assert_eq 0.1.0 "$(main_version_in "$BARE")" "remote main still the old version"
}

test_the_real_origin_is_never_used() {
  given_remote_and_clone
  assert_eq "upstream" "$(git -C "$WORK" remote)" "the clone has only the local remote"
  assert_contains "$(git -C "$WORK" remote get-url upstream)" "$TEST_ROOT" "and it is under the temp dir"
}

run_tests
