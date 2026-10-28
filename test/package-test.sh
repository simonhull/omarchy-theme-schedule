source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

test_make_install_lays_out_the_package() {
  local dest="$TEST_ROOT/pkg"
  make -s -C "$REPO" DESTDIR="$dest" PREFIX=/usr install >/dev/null
  assert_eq "$(cat <<'EOF'
/usr/bin/omarchy-theme-schedule
/usr/lib/systemd/user/omarchy-theme-schedule.service
/usr/lib/systemd/user/omarchy-theme-schedule.timer
/usr/share/licenses/omarchy-theme-schedule/LICENSE
/usr/share/omarchy-theme-schedule/menu.jsonc
/usr/share/omarchy-theme-schedule/schedule.sh
/usr/share/omarchy-theme-schedule/sun.awk
EOF
)" "$(cd "$dest" && find . -type f | sed 's|^\.||' | sort)" "installed files"
  assert_status 0 "binary is executable" test -x "$dest/usr/bin/omarchy-theme-schedule"
  # The omarchy dispatcher only routes commands linked into its own bin dir.
  assert_eq /usr/bin/omarchy-theme-schedule "$(readlink "$dest/usr/share/omarchy/bin/omarchy-theme-schedule")" \
    "linked where omarchy theme schedule finds it"
}

test_make_uninstall_removes_everything_install_put_in_place() {
  local dest="$TEST_ROOT/pkg"
  make -s -C "$REPO" DESTDIR="$dest" PREFIX=/usr install >/dev/null
  make -s -C "$REPO" DESTDIR="$dest" PREFIX=/usr uninstall >/dev/null
  assert_eq "" "$(find "$dest" -type f -o -type l)" "no files or links left"
  assert_eq "" "$(find "$dest" -name 'omarchy-theme-schedule*')" "no package directories left"
}

test_installed_binary_finds_its_library() {
  local dest="$TEST_ROOT/pkg"
  make -s -C "$REPO" DESTDIR="$dest" PREFIX=/usr install >/dev/null
  assert_contains "$(OMARCHY_THEME_SCHEDULE_LIB="$dest/usr/share/omarchy-theme-schedule" "$dest/usr/bin/omarchy-theme-schedule" status 2>&1)" \
    "Theme schedule: off" "runs from the installed tree"
}

test_pkgbuild_parses() {
  assert_status 0 "makepkg --printsrcinfo" bash -c "cd '$REPO' && makepkg --printsrcinfo"
}

run_tests
