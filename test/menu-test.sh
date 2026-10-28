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
  assert_contains "$(stub_log)" "menu Theme schedule: [2. 07:00 (07:00) → Flexoki Light] [1. 19:00 (19:00) → Tokyo Night]" "rows"
}

test_menu_slots_remove() {
  write_schedule '{"slots":[{"at":"07:00","theme":"a"},{"at":"19:00","theme":"b"}]}'
  set_now "2026-10-28 12:00"
  answer "2. 19:00 (19:00) → B" "Remove"
  omarchy-theme-schedule menu slots
  assert_eq '[{"at":"07:00","theme":"a"}]' "$(read_schedule)" "removed"
}

test_menu_slots_change_theme() {
  add_theme a everforest
  write_schedule '{"slots":[{"at":"07:00","theme":"a"}]}'
  set_now "2026-10-28 12:00"
  answer "1. 07:00 (07:00) → A" "Change theme" "Everforest"
  omarchy-theme-schedule menu slots
  assert_eq '[{"at":"07:00","theme":"everforest"}]' "$(read_schedule)" "theme changed"
}

test_menu_slots_change_time() {
  add_theme a
  write_schedule '{"slots":[{"at":"07:00","theme":"a"}]}'
  set_now "2026-10-28 12:00"
  answer "1. 07:00 (07:00) → A" "Change time" "Sunrise" "1 hour after"
  omarchy-theme-schedule menu slots
  assert_eq '[{"at":"sunrise+1h","theme":"a"}]' "$(read_schedule)" "time changed"
}

test_menu_slots_without_slots_offers_add() {
  omarchy-theme-schedule menu slots
  assert_contains "$(stub_log)" "menu When:" "goes straight to adding"
}

run_tests
