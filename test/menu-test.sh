# shellcheck shell=bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

MENU() {
  echo "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
}

# Parses a menu file the way the shell does (MenuModel.js stripJsonc): drop
# whole-line // comments, then trailing commas before } or ].
menu_json() {
  grep -vE '^[[:space:]]*//' "$(MENU)" | perl -0pe 's/,(\s*[}\]])/$1/g' | jq -c .
}

test_setup_creates_the_menu_file() {
  assert_status 0 "setup" omarchy-theme-schedule setup
  assert_eq '"Theme Schedule"' "$(menu_json | jq '."appearance.theme-schedule".label')" "parent row"
  assert_eq '"omarchy-theme-schedule menu add"' "$(menu_json | jq '."appearance.theme-schedule.add".action')" "add row"
}

test_setup_keeps_existing_rows_and_stays_valid() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n  // mine\n  "personal": {"icon":"","label":"Personal"},\n  "personal.notes": {"label":"Notes","action":"true"}\n}\n' >"$(MENU)"
  omarchy-theme-schedule setup
  assert_eq '"Notes"' "$(menu_json | jq '."personal.notes".label')" "user row kept"
  assert_eq '"Theme Schedule"' "$(menu_json | jq '."appearance.theme-schedule".label')" "rows added"
}

test_setup_twice_adds_one_block() {
  omarchy-theme-schedule setup
  omarchy-theme-schedule setup
  assert_eq 1 "$(grep -c 'theme-schedule:begin' "$(MENU)")" "one block"
}

test_teardown_restores_the_file_exactly() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n  "personal": {"label":"Personal"}\n}\n' >"$(MENU)"
  cp "$(MENU)" "$TEST_ROOT/before"
  omarchy-theme-schedule setup
  omarchy-theme-schedule teardown
  assert_status 0 "byte-identical" cmp "$TEST_ROOT/before" "$(MENU)"
}

test_teardown_without_a_block_is_harmless() {
  assert_status 0 "no file" omarchy-theme-schedule teardown
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n}\n' >"$(MENU)"
  assert_status 0 "no block" omarchy-theme-schedule teardown
  assert_eq $'{\n}' "$(cat "$(MENU)")" "untouched"
}

test_setup_refuses_a_file_it_cannot_place_rows_in() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{"personal": {"label":"Personal"}}\n' >"$(MENU)"
  cp "$(MENU)" "$TEST_ROOT/before"
  assert_status 1 "fails" omarchy-theme-schedule setup
  assert_status 0 "untouched" cmp "$TEST_ROOT/before" "$(MENU)"
}

test_setup_keeps_file_permissions() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n}\n' >"$(MENU)"
  chmod 644 "$(MENU)"
  omarchy-theme-schedule setup
  assert_eq 644 "$(stat -c %a "$(MENU)")" "mode kept"
}

test_menu_add_at_an_offset_from_sunset() {
  add_theme tokyo-night
  answer "Sunset" "30 minutes before" "Tokyo Night"
  assert_status 0 "add" omarchy-theme-schedule menu add
  assert_eq '[{"at":"sunset-30m","theme":"tokyo-night"}]' "$(read_schedule)" "stored"
  assert_contains "$(stub_log)" "menu Theme: [Tokyo Night]" "themes offered by display name"
}

test_menu_add_exactly_at_sunrise() {
  add_theme flexoki-light
  answer "Sunrise" "Exactly" "Flexoki Light"
  omarchy-theme-schedule menu add
  assert_eq '[{"at":"sunrise","theme":"flexoki-light"}]' "$(read_schedule)" "stored"
}

test_menu_add_at_a_typed_time() {
  add_theme flexoki-light
  answer "Specific time" "06:45" "Flexoki Light"
  omarchy-theme-schedule menu add
  assert_eq '[{"at":"06:45","theme":"flexoki-light"}]' "$(read_schedule)" "stored"
}

test_menu_add_with_a_bad_typed_time_notifies() {
  add_theme flexoki-light
  answer "Specific time" "6:45"
  omarchy-theme-schedule menu add
  assert_contains "$(stub_log)" "Not a schedule time: 6:45" "notified"
  assert_status 1 "nothing stored" test -f "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

test_menu_add_dismissed_changes_nothing() {
  assert_status 0 "dismissing is not an error" omarchy-theme-schedule menu add
  assert_status 1 "nothing stored" test -f "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

test_menu_slots_lists_today_in_time_order() {
  write_schedule '{"slots":[{"at":"19:00","theme":"tokyo-night"},{"at":"07:00","theme":"flexoki-light"}]}'
  set_now "2026-10-28 12:00"
  omarchy-theme-schedule menu slots
  assert_contains "$(stub_log)" "menu Theme schedule: [2. 07:00 " "rows"
}

test_menu_slots_remove() {
  write_schedule '{"slots":[{"at":"07:00","theme":"a"},{"at":"19:00","theme":"b"}]}'
  set_now "2026-10-28 12:00"
  answer "2. 19:00 → B" "Remove"
  omarchy-theme-schedule menu slots
  assert_eq '[{"at":"07:00","theme":"a"}]' "$(read_schedule)" "removed"
}

test_menu_slots_change_theme() {
  add_theme a everforest
  write_schedule '{"slots":[{"at":"07:00","theme":"a"}]}'
  set_now "2026-10-28 12:00"
  answer "1. 07:00 → A" "Change theme" "Everforest"
  omarchy-theme-schedule menu slots
  assert_eq '[{"at":"07:00","theme":"everforest"}]' "$(read_schedule)" "theme changed"
}

test_menu_slots_change_time() {
  add_theme a
  write_schedule '{"slots":[{"at":"07:00","theme":"a"}]}'
  set_now "2026-10-28 12:00"
  answer "1. 07:00 → A" "Change time" "Sunrise" "1 hour after"
  omarchy-theme-schedule menu slots
  assert_eq '[{"at":"sunrise+1h","theme":"a"}]' "$(read_schedule)" "time changed"
}

test_menu_slots_without_slots_offers_add() {
  omarchy-theme-schedule menu slots
  assert_contains "$(stub_log)" "menu When:" "goes straight to adding"
}

# --- damaged, linked and unusual menu files ---

BEGIN='  // theme-schedule:begin (x)'
END='  // theme-schedule:end'

assert_setup_and_teardown_refuse() {
  local message=$1
  cp "$(MENU)" "$TEST_ROOT/before"
  assert_status 1 "$message: setup refuses" omarchy-theme-schedule setup
  assert_status 0 "$message: setup leaves the file" cmp "$TEST_ROOT/before" "$(MENU)"
  assert_status 1 "$message: teardown refuses" omarchy-theme-schedule teardown
  assert_status 0 "$message: teardown leaves the file" cmp "$TEST_ROOT/before" "$(MENU)"
  assert_contains "$(omarchy-theme-schedule setup 2>&1 >/dev/null)" "unfinished theme-schedule block" "$message: explains"
  assert_eq "" "$(ls "$(dirname "$(MENU)")" | grep -v '^omarchy-menu.jsonc$')" "$message: no temp files left"
}

test_begin_marker_without_end_is_refused() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n%s\n  "keep": {"label":"Keep"},\n  "keep2": {"label":"Keep"}\n}\n' "$BEGIN" >"$(MENU)"
  assert_setup_and_teardown_refuse "begin only"
}

test_end_marker_without_begin_is_refused() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n  "keep": {"label":"Keep"},\n%s\n  "keep2": {"label":"Keep"}\n}\n' "$END" >"$(MENU)"
  assert_setup_and_teardown_refuse "end only"
}

test_end_marker_before_begin_is_refused() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n%s\n  "keep": {"label":"Keep"},\n%s\n}\n' "$END" "$BEGIN" >"$(MENU)"
  assert_setup_and_teardown_refuse "reversed"
}

test_two_blocks_are_refused() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n%s\n%s\n  "keep": {"label":"Keep"},\n%s\n%s\n}\n' "$BEGIN" "$END" "$BEGIN" "$END" >"$(MENU)"
  assert_setup_and_teardown_refuse "two blocks"
}

test_setup_replaces_an_old_block_in_one_pass() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n%s\n  "old": {"label":"Old"},\n%s\n  "keep": {"label":"Keep"}\n}\n' "$BEGIN" "$END" >"$(MENU)"
  assert_status 0 "setup" omarchy-theme-schedule setup
  assert_eq 1 "$(grep -c 'theme-schedule:begin' "$(MENU)")" "one block"
  assert_eq null "$(menu_json | jq '.old')" "old row gone"
  assert_eq '"Keep"' "$(menu_json | jq '.keep.label')" "user row kept"
}

test_symlinked_menu_file_stays_a_link() {
  mkdir -p "$(dirname "$(MENU)")" "$TEST_ROOT/dotfiles"
  printf '{\n  "personal": {"label":"Personal"}\n}\n' >"$TEST_ROOT/dotfiles/omarchy-menu.jsonc"
  cp "$TEST_ROOT/dotfiles/omarchy-menu.jsonc" "$TEST_ROOT/before"
  ln -s "$TEST_ROOT/dotfiles/omarchy-menu.jsonc" "$(MENU)"
  assert_status 0 "setup" omarchy-theme-schedule setup
  assert_status 0 "still a link" test -L "$(MENU)"
  assert_contains "$(cat "$TEST_ROOT/dotfiles/omarchy-menu.jsonc")" "theme-schedule:begin" "target has the block"
  assert_status 0 "teardown" omarchy-theme-schedule teardown
  assert_status 0 "still a link" test -L "$(MENU)"
  assert_status 0 "target restored" cmp "$TEST_ROOT/before" "$TEST_ROOT/dotfiles/omarchy-menu.jsonc"
}

test_setup_accepts_an_opening_brace_with_a_comment() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{ // my rows\n  "personal": {"label":"Personal"}\n}\n' >"$(MENU)"
  cp "$(MENU)" "$TEST_ROOT/before"
  assert_status 0 "setup" omarchy-theme-schedule setup
  # Not parsed: the shell itself only drops whole-line comments, so this file is
  # the user's own problem. What matters is where the block went.
  assert_eq '{ // my rows' "$(sed -n 1p "$(MENU)")" "opening line kept"
  assert_contains "$(sed -n 2p "$(MENU)")" "theme-schedule:begin" "block right after it"
  assert_status 0 "teardown" omarchy-theme-schedule teardown
  assert_status 0 "round trip" cmp "$TEST_ROOT/before" "$(MENU)"
}

test_setup_treats_an_empty_file_as_missing() {
  mkdir -p "$(dirname "$(MENU)")"
  : >"$(MENU)"
  assert_status 0 "empty" omarchy-theme-schedule setup
  assert_eq '"Theme Schedule"' "$(menu_json | jq '."appearance.theme-schedule".label')" "rows added"
  printf ' \n\n' >"$(MENU)"
  omarchy-theme-schedule teardown
  assert_status 0 "blank" omarchy-theme-schedule setup
  assert_eq '"Theme Schedule"' "$(menu_json | jq '."appearance.theme-schedule".label')" "rows added to blank"
}

test_setup_refuses_an_items_wrapper() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n  "items": {\n    "personal": {"label":"Personal"}\n  }\n}\n' >"$(MENU)"
  cp "$(MENU)" "$TEST_ROOT/before"
  assert_status 1 "refuses" omarchy-theme-schedule setup
  assert_contains "$(omarchy-theme-schedule setup 2>&1 >/dev/null)" 'wraps its rows in "items"' "explains"
  assert_status 0 "untouched" cmp "$TEST_ROOT/before" "$(MENU)"
}

test_setup_leaves_no_temp_files_when_refusing() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{"personal": {"label":"Personal"}}\n' >"$(MENU)"
  omarchy-theme-schedule setup 2>/dev/null
  assert_eq "omarchy-menu.jsonc" "$(ls "$(dirname "$(MENU)")")" "only the user file"
}

test_block_goes_after_the_first_opening_brace_only() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n  "a": {"label":"A"},\n  "b": {\n    "label":"B"\n  }\n}\n' >"$(MENU)"
  printf '{\n  "a": {"label":"A"},\n  "b": {\n    "label":"B"\n  }\n}\n' >"$TEST_ROOT/before"
  omarchy-theme-schedule setup
  assert_eq '{' "$(head -n 1 "$(MENU)")" "first line"
  assert_contains "$(sed -n 2p "$(MENU)")" "theme-schedule:begin" "block second"
  assert_eq 1 "$(grep -c 'theme-schedule:begin' "$(MENU)")" "one block"
  omarchy-theme-schedule teardown
  assert_status 0 "round trip" cmp "$TEST_ROOT/before" "$(MENU)"
}

test_menu_rows_have_the_right_when_and_action() {
  omarchy-theme-schedule setup
  local p='."appearance.theme-schedule'
  assert_eq '"! omarchy-toggle-enabled theme-schedule"' "$(menu_json | jq "$p.on\".when")" "on when"
  assert_eq '"omarchy-theme-schedule on"' "$(menu_json | jq "$p.on\".action")" "on action"
  assert_eq '"omarchy-toggle-enabled theme-schedule"' "$(menu_json | jq "$p.off\".when")" "off when"
  assert_eq '"omarchy-theme-schedule off"' "$(menu_json | jq "$p.off\".action")" "off action"
  assert_eq null "$(menu_json | jq "$p.slots\".when")" "slots when"
  assert_eq '"omarchy-theme-schedule menu slots"' "$(menu_json | jq "$p.slots\".action")" "slots action"
  assert_eq null "$(menu_json | jq "$p.add\".when")" "add when"
  assert_eq '"omarchy-theme-schedule menu add"' "$(menu_json | jq "$p.add\".action")" "add action"
  assert_eq '"omarchy-toggle-enabled theme-schedule"' "$(menu_json | jq "$p.apply\".when")" "apply when"
  assert_eq '"omarchy-theme-schedule apply --force"' "$(menu_json | jq "$p.apply\".action")" "apply action"

  local when='"[[ $(omarchy-theme-schedule check-update --cached) == available* ]]"'
  local action='"omarchy-launch-floating-terminal-with-presentation omarchy-theme-schedule update"'
  assert_eq "$when" "$(menu_json | jq "$p.update\".when")" "appearance update when"
  assert_eq "$action" "$(menu_json | jq "$p.update\".action")" "appearance update action"
  assert_eq '"Update Theme Schedule"' "$(menu_json | jq "$p.update\".label")" "appearance update label"
  assert_eq "$when" "$(menu_json | jq '."update.theme-schedule".when')" "update row when"
  assert_eq "$action" "$(menu_json | jq '."update.theme-schedule".action')" "update row action"
  assert_eq '"Theme Schedule"' "$(menu_json | jq '."update.theme-schedule".label')" "update row label"
  # The update row wears the package's own glyph, the parent row's.
  assert_eq "$(menu_json | jq '."appearance.theme-schedule".icon')" "$(menu_json | jq '."update.theme-schedule".icon')" "same glyph as the parent row"
}

test_the_update_row_is_inside_the_one_marked_block() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{\n  "personal": {"label":"Personal"}\n}\n' >"$(MENU)"
  cp "$(MENU)" "$TEST_ROOT/before"
  omarchy-theme-schedule setup
  local begin end row
  begin=$(grep -n 'theme-schedule:begin' "$(MENU)" | cut -d: -f1)
  end=$(grep -n 'theme-schedule:end' "$(MENU)" | cut -d: -f1)
  row=$(grep -n '"update.theme-schedule"' "$(MENU)" | cut -d: -f1)
  TESTS_RUN=$((TESTS_RUN + 1))
  ((begin < row && row < end)) || fail "update row at $row, block at $begin-$end"
  assert_eq 1 "$(grep -c 'theme-schedule:begin' "$(MENU)")" "one block"
  omarchy-theme-schedule teardown
  assert_status 0 "teardown takes the update row too" cmp "$TEST_ROOT/before" "$(MENU)"
}

test_menu_add_with_an_empty_typed_time_is_silent() {
  add_theme flexoki-light
  answer "Specific time" "<empty>"
  assert_status 0 "returns" omarchy-theme-schedule menu add
  assert_not_contains "$(stub_log)" "notify" "no notification"
  assert_status 1 "nothing stored" test -f "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

test_menu_add_trims_the_typed_time() {
  add_theme flexoki-light
  answer "Specific time" " 06:45 " "Flexoki Light"
  omarchy-theme-schedule menu add
  assert_eq '[{"at":"06:45","theme":"flexoki-light"}]' "$(read_schedule)" "stored trimmed"
}

test_menu_add_with_an_uninstalled_theme_notifies_the_error() {
  answer "Sunrise" "Exactly" "Ghost Theme"
  assert_status 1 "menu add reports failure" omarchy-theme-schedule menu add
  assert_contains "$(stub_log)" "Theme schedule not changed" "title"
  assert_contains "$(stub_log)" "is not installed" "reason"
  assert_status 1 "nothing stored" test -f "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

test_menu_run_without_error_text_still_has_a_body() {
  menu_run_probe() { return 1; }
  source <(sed -n '/^menu_run() {/,/^}/p' "$REPO/bin/omarchy-theme-schedule")
  source <(sed -n '/^t() {/,/^}/p' "$REPO/bin/omarchy-theme-schedule")
  declare -gA TS_ENGLISH=([themeSchedule.menuFailed]="Theme schedule not changed")
  TS_ICON=x
  menu_run menu_run_probe
  assert_contains "$(stub_log)" "notify -g x -u normal Theme schedule not changed Theme schedule not changed" "generic body"
}

test_menu_add_dismissed_at_the_theme_stores_nothing() {
  answer "Sunrise" "Exactly"
  assert_status 0 "returns" omarchy-theme-schedule menu add
  assert_status 1 "nothing stored" test -f "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

test_menu_add_passes_maxheight_to_the_theme_picker() {
  add_theme tokyo-night
  answer "Sunrise" "Exactly" "Tokyo Night"
  omarchy-theme-schedule menu add
  assert_contains "$(stub_log)" "menu Theme: [Tokyo Night] args: --maxheight 520" "flag reaches the picker"
}

test_menu_slots_full_row_text_for_sun_and_clock_slots() {
  set_location 51.5 -0.12 London
  write_schedule '{"slots":[{"at":"sunset-30m","theme":"tokyo-night"},{"at":"07:00","theme":"flexoki-light"}]}'
  set_now "2026-10-28 12:00"
  omarchy-theme-schedule menu slots
  local line
  line=$(grep '^menu Theme schedule:' "$STUB_LOG")
  assert_eq "menu Theme schedule: [2. 07:00 → Flexoki Light] [1. Sunset-30m (16:12) → Tokyo Night]" "$line" "exact rows, today only"
}

# --- the post-update hook ---

HOOK() {
  echo "$HOME/.config/omarchy/hooks/post-update.d/omarchy-theme-schedule"
}

test_setup_installs_the_post_update_hook() {
  assert_status 0 "setup" omarchy-theme-schedule setup
  assert_contains "$(stub_log)" "hook-install post-update " "installed as a post-update hook"
  assert_status 0 "hook is in place under its own name" test -x "$(HOOK)"
  assert_status 0 "same file as the shipped one" cmp "$REPO/lib/theme-schedule/post-update.hook" "$(HOOK)"
}

test_setup_twice_leaves_one_hook() {
  omarchy-theme-schedule setup
  omarchy-theme-schedule setup
  assert_eq "omarchy-theme-schedule" "$(ls "$HOME/.config/omarchy/hooks/post-update.d")" "one file"
  assert_status 0 "same file as the shipped one" cmp "$REPO/lib/theme-schedule/post-update.hook" "$(HOOK)"
}

test_setup_leaves_other_hooks_alone() {
  mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
  echo mine >"$HOME/.config/omarchy/hooks/post-update.d/mine"
  omarchy-theme-schedule setup
  omarchy-theme-schedule teardown
  assert_eq "mine" "$(ls "$HOME/.config/omarchy/hooks/post-update.d")" "only ours removed"
}

test_teardown_removes_the_hook() {
  omarchy-theme-schedule setup
  assert_status 0 "teardown" omarchy-theme-schedule teardown
  assert_status 1 "hook gone" test -e "$(HOOK)"
}

test_teardown_without_the_hook_is_fine() {
  assert_status 0 "no hook, no menu file" omarchy-theme-schedule teardown
  omarchy-theme-schedule setup
  rm "$(HOOK)"
  assert_status 0 "no hook" omarchy-theme-schedule teardown
}

test_teardown_removes_the_hook_even_without_a_menu_block() {
  mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
  echo x >"$(HOOK)"
  assert_status 0 "teardown" omarchy-theme-schedule teardown
  assert_status 1 "hook gone" test -e "$(HOOK)"
}

test_a_failed_hook_install_warns_but_setup_succeeds() {
  local err
  export STUB_HOOK_INSTALL_FAILS=1
  assert_status 0 "setup" omarchy-theme-schedule setup
  err=$(omarchy-theme-schedule setup 2>&1 >/dev/null)
  assert_contains "$err" "update notifications" "warns"
  assert_eq '"Theme Schedule"' "$(menu_json | jq '."appearance.theme-schedule".label')" "menu block still added"
}

test_setup_does_not_install_the_hook_when_the_menu_is_refused() {
  mkdir -p "$(dirname "$(MENU)")"
  printf '{"personal": {"label":"Personal"}}\n' >"$(MENU)"
  omarchy-theme-schedule setup 2>/dev/null
  assert_status 1 "no hook" test -e "$(HOOK)"
}

test_the_hook_is_a_noop_without_the_command_and_runs_check_update_with_it() {
  local hook="$REPO/lib/theme-schedule/post-update.hook"
  assert_eq "#!/bin/bash" "$(head -n 1 "$hook")" "shebang"
  # An empty PATH, so an installed copy on this machine does not count.
  mkdir "$TEST_ROOT/empty"
  assert_status 0 "no command, no error" env PATH="$TEST_ROOT/empty" /usr/bin/bash "$hook"
  assert_eq "" "$(env PATH="$TEST_ROOT/empty" /usr/bin/bash "$hook" 2>&1)" "and says nothing"
  stub omarchy-theme-schedule 'echo "schedule $*" >>"$STUB_LOG"; exit 3'
  assert_status 0 "never fails" bash "$hook"
  assert_contains "$(stub_log)" "schedule check-update --notify" "checks and notifies"
}

run_tests
