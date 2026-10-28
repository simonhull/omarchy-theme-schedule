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

run_tests
