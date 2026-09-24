#!/usr/bin/env bash
# Test harness for ai-meter. No external framework: each test_* function returns 0/1 and
# sets $ERR on failure; run() prints "PASS <name>" / "FAIL <name>: <reason>". Exits 0 only if
# every named test passed. Runs fully offline: providers and curl are stubbed under tests/fixtures.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MB="$REPO_DIR/plasmoid/org.mat.aimeter/contents/collector/ai-meter"
FIXTURES="$SCRIPT_DIR/fixtures"
PROVIDERS="$FIXTURES/providers"
CURL_STUB="$FIXTURES/curl-stub.sh"

PASS_COUNT=0
FAIL_COUNT=0
ERR=""

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

run() {
  local name="$1" fn="$2"
  ERR=""
  if "$fn"; then
    pass "$name"
  else
    fail "$name" "${ERR:-assertion failed}"
  fi
}

# Sets $ERR and returns 1 when actual != expected.
check() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" != "$expected" ]; then
    ERR="$label: expected [$expected] got [$actual]"
    return 1
  fi
  return 0
}

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

# Not run via $(...): export inside a subshell never reaches the caller. Sets $ENV_DIR.
new_env() {
  ENV_DIR=$(mktemp -d "$WORKROOT/env.XXXXXX")
  mkdir -p "$ENV_DIR/state"
  export AI_METER_STATE="$ENV_DIR/state"
  export AI_METER_CONFIG="$ENV_DIR/config.json"
  export AI_METER_PUSH_CONFIG="$ENV_DIR/push.json"
  export AI_METER_PROVIDERS="$PROVIDERS"
  export AI_METER_TIMEOUT=40
  unset AI_METER_FIXTURE AI_METER_CURL AI_METER_TOKEN_URL AI_METER_FCM_URL
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT AI_METER_TEST_REASON
  unset AI_METER_TEST_COUNTER AI_METER_TEST_ENVFILE
  unset MB_CURL_FAIL MB_CURL_TOKEN_COUNT MB_CURL_SEND_COUNT
  unset MB_CURL_TOKEN_ASSERTION MB_CURL_SEND_BODY MB_CURL_ACCESS_TOKEN MB_CURL_EXPIRES_IN
  unset AI_METER_LISTEN_MAX_CONNECTS AI_METER_RECONNECT_DELAY AI_METER_NOW_MS
  unset MB_CURL_ARGV_LOG MB_CURL_SSE_DIR MB_CURL_SSE_CONNECT_COUNT MB_CURL_SSE_AUTH_LOG
}

write_config() { printf '%s' "$2" > "$1/config.json"; }

decode_b64url() {
  local s="$1"
  s=$(printf '%s' "$s" | tr '_-' '/+')
  local pad=$(( (4 - ${#s} % 4) % 4 ))
  [ "$pad" -gt 0 ] && s="$s$(printf '=%.0s' $(seq 1 "$pad"))"
  printf '%s' "$s" | base64 -d
}

make_service_account() {
  local dir="$1"
  openssl genrsa -out "$dir/key.pem" 2048 >/dev/null 2>&1
  openssl rsa -in "$dir/key.pem" -pubout -out "$dir/key.pub.pem" >/dev/null 2>&1
  local pk; pk=$(cat "$dir/key.pem")
  jq -n --arg email "svc@example-project.iam.gserviceaccount.com" --arg key "$pk" \
    --arg turi "https://oauth2.example.test/token" \
    '{client_email: $email, private_key: $key, token_uri: $turi}' > "$dir/sa.json"
}

write_push_config() {
  local dir="$1" sa_path="$2" topic="${3:-meters}"
  jq -n --arg pid "proj1" --arg sa "$sa_path" --arg topic "$topic" \
    '{projectId: $pid, serviceAccount: $sa, topic: $topic}' > "$dir/push.json"
}

write_listen_push_config() {
  local dir="$1" sa_path="$2" topic="$3" db_url="$4" refresh_key="$5"
  jq -n --arg pid "proj1" --arg sa "$sa_path" --arg topic "$topic" --arg db "$db_url" --arg key "$refresh_key" \
    '{projectId: $pid, serviceAccount: $sa, topic: $topic, databaseUrl: $db, refreshKey: $key}' > "$dir/push.json"
}

sse_event() {
  local val="$1"
  printf 'event: put\ndata: {"path":"/","data":%s}\n\n' "$val"
}

CLAUDE_CFG='{"v":1,"meters":[{"id":"m1","type":"claude","label":"Claude","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'

# ================= mapping =================

test_mapping_claude() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":9,"reset_in":3600},"seven":{"pct":40,"reset_in":86400},"model":{"name":"Fable","pct":12,"reset_in":86400}}'
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT

  local bar_count; bar_count=$(jq '.meters[0].bars | length' <<<"$out")
  check "$bar_count" "3" "bar count with model" || return 1
  local ts; ts=$(jq -r '.ts' <<<"$out")

  check "$(jq -r '.meters[0].bars[0].k' <<<"$out")" "5h" "bar0 k" || return 1
  check "$(jq -r '.meters[0].bars[0].label' <<<"$out")" "5h" "bar0 label" || return 1
  check "$(jq -r '.meters[0].bars[0].pct' <<<"$out")" "9" "bar0 pct" || return 1
  check "$(jq -r '.meters[0].bars[0].win' <<<"$out")" "18000" "bar0 win" || return 1
  check "$(jq -r '.meters[0].bars[0].reset_at' <<<"$out")" "$((ts + 3600))" "bar0 reset_at" || return 1

  check "$(jq -r '.meters[0].bars[1].k' <<<"$out")" "7d" "bar1 k" || return 1
  check "$(jq -r '.meters[0].bars[1].win' <<<"$out")" "604800" "bar1 win" || return 1

  check "$(jq -r '.meters[0].bars[2].k' <<<"$out")" "model" "bar2 k" || return 1
  check "$(jq -r '.meters[0].bars[2].label' <<<"$out")" "Fable" "bar2 label" || return 1
  check "$(jq -r '.meters[0].bars[2].pct' <<<"$out")" "12" "bar2 pct" || return 1
  check "$(jq -r '.meters[0].bars[2].win' <<<"$out")" "604800" "bar2 win" || return 1

  check "$(jq -r '.meters[0].plan' <<<"$out")" "null" "plan always null for claude" || return 1

  local d2; new_env; d2="$ENV_DIR"
  write_config "$d2" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":1,"reset_in":10},"seven":{"pct":2,"reset_in":20},"model":null}'
  local out2; out2=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT
  check "$(jq '.meters[0].bars | length' <<<"$out2")" "2" "bar count with null model" || return 1
  return 0
}

test_mapping_codex() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[{"id":"m1","type":"codex","label":"Codex","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"live","age":0,"plan":"plus","five":{"pct":9,"reset_in":3600,"fresh":true},"seven":{"pct":40,"reset_in":86400,"fresh":false}}'
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT

  check "$(jq '.meters[0].bars | length' <<<"$out")" "2" "bar count" || return 1
  check "$(jq -r '.meters[0].bars[0].k' <<<"$out")" "5h" "bar0 k" || return 1
  check "$(jq -r '.meters[0].bars[0].win' <<<"$out")" "18000" "bar0 win" || return 1
  check "$(jq -r '.meters[0].bars[0].fresh' <<<"$out")" "true" "bar0 fresh" || return 1
  check "$(jq -r '.meters[0].bars[1].k' <<<"$out")" "7d" "bar1 k" || return 1
  check "$(jq -r '.meters[0].bars[1].win' <<<"$out")" "604800" "bar1 win" || return 1
  check "$(jq -r '.meters[0].plan' <<<"$out")" "plus" "plan" || return 1
  return 0
}

test_mapping_grok() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[{"id":"m1","type":"grok","label":"Grok","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"live","age":0,"plan":"SuperGrok","five":{"pct":5,"reset_in":100,"fresh":false},"seven":{"pct":40,"reset_in":604800,"fresh":false}}'
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT

  check "$(jq -r '.meters[0].bars[0].k' <<<"$out")" "cli" "bar0 k" || return 1
  check "$(jq -r '.meters[0].bars[0].label' <<<"$out")" "CLI" "bar0 label" || return 1
  check "$(jq -r '.meters[0].bars[0].win' <<<"$out")" "604800" "bar0 win" || return 1
  check "$(jq -r '.meters[0].bars[1].k' <<<"$out")" "7d" "bar1 k" || return 1
  check "$(jq -r '.meters[0].bars[1].win' <<<"$out")" "604800" "bar1 win" || return 1
  check "$(jq -r '.meters[0].plan' <<<"$out")" "SuperGrok" "plan" || return 1
  return 0
}

test_mapping_cursor() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[{"id":"m1","type":"cursor","label":"Cursor","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"live","age":0,"plan":"Pro","cycle_sec":123456,"five":{"pct":9,"reset_in":100,"fresh":false},"seven":{"pct":40,"reset_in":200,"fresh":false},"grok":{"pct":5,"reset_in":50,"fresh":false,"week_sec":77777}}'
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT

  check "$(jq '.meters[0].bars | length' <<<"$out")" "3" "bar count with grok" || return 1
  check "$(jq -r '.meters[0].bars[0].k' <<<"$out")" "models" "bar0 k" || return 1
  check "$(jq -r '.meters[0].bars[0].label' <<<"$out")" "Models" "bar0 label" || return 1
  check "$(jq -r '.meters[0].bars[0].win' <<<"$out")" "123456" "bar0 win from cycle_sec" || return 1
  check "$(jq -r '.meters[0].bars[1].k' <<<"$out")" "other" "bar1 k" || return 1
  check "$(jq -r '.meters[0].bars[1].label' <<<"$out")" "Other" "bar1 label" || return 1
  check "$(jq -r '.meters[0].bars[1].win' <<<"$out")" "123456" "bar1 win from cycle_sec" || return 1
  check "$(jq -r '.meters[0].bars[2].k' <<<"$out")" "grok" "bar2 k" || return 1
  check "$(jq -r '.meters[0].bars[2].label' <<<"$out")" "Grok" "bar2 label" || return 1
  check "$(jq -r '.meters[0].bars[2].win' <<<"$out")" "77777" "bar2 win from week_sec" || return 1
  check "$(jq -r '.meters[0].plan' <<<"$out")" "Pro" "plan" || return 1

  local d2; new_env; d2="$ENV_DIR"
  write_config "$d2" '{"v":1,"meters":[{"id":"m1","type":"cursor","label":"Cursor","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"live","age":0,"plan":"Pro","five":{"pct":9,"reset_in":100,"fresh":false},"seven":{"pct":40,"reset_in":200,"fresh":false},"grok":null}'
  local out2; out2=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT
  check "$(jq '.meters[0].bars | length' <<<"$out2")" "2" "bar count without grok" || return 1
  check "$(jq -r '.meters[0].bars[0].win' <<<"$out2")" "2592000" "default cycle_sec win" || return 1
  return 0
}

test_hide_drops_bars() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[{"id":"m1","type":"claude","label":"Claude","sub":"","panel":true,"phone":true,"hide":["7d","model"],"icon":"","opts":{}}]}'
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":9,"reset_in":3600},"seven":{"pct":40,"reset_in":86400},"model":{"name":"Fable","pct":12,"reset_in":86400}}'
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_OUT
  check "$(jq -r '[.meters[0].bars[].k] | join(",")' <<<"$out")" "5h" "only 5h remains" || return 1
  return 0
}

test_sub_empty_is_null() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[
    {"id":"m1","type":"claude","label":"Claude","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}},
    {"id":"m2","type":"codex","label":"Codex","sub":"Work","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}
  ]}'
  export AI_METER_TEST_MODE=ok
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE
  check "$(jq -r '.meters[0].sub' <<<"$out")" "null" "empty sub -> null" || return 1
  check "$(jq -r '.meters[1].sub' <<<"$out")" "Work" "non-empty sub kept" || return 1
  return 0
}

test_order_follows_config() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[
    {"id":"z1","type":"claude","label":"Z","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}},
    {"id":"a1","type":"codex","label":"A","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}},
    {"id":"m1","type":"grok","label":"M","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}
  ]}'
  export AI_METER_TEST_MODE=ok
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE
  check "$(jq -r '[.meters[].id] | join(",")' <<<"$out")" "z1,a1,m1" "order preserved" || return 1
  return 0
}

test_claude_isolated_account_disables_browser() {
  local d; new_env; d="$ENV_DIR"
  local claudeDir="$d/fake-claude"
  mkdir -p "$claudeDir"
  write_config "$d" "$(jq -n --arg cd "$claudeDir" \
    '{v:1, meters:[{id:"m1",type:"claude",label:"Claude",sub:"",panel:true,phone:true,hide:[],icon:"",opts:{claudeDir:$cd,cookiesPath:""}}]}')"
  export AI_METER_TEST_ENVFILE="$d/envdump.txt"
  export AI_METER_TEST_MODE=ok
  "$MB" collect >/dev/null
  unset AI_METER_TEST_ENVFILE AI_METER_TEST_MODE
  [ -s "$d/envdump.txt" ] || { ERR="no envdump captured"; return 1; }
  local usage_dir cookies
  usage_dir=$(grep '^CLAUDE_USAGE_DIR=' "$d/envdump.txt" | cut -d= -f2-)
  cookies=$(grep '^CLAUDE_CHROME_COOKIES=' "$d/envdump.txt" | cut -d= -f2-)
  check "$usage_dir" "$claudeDir/usage" "CLAUDE_USAGE_DIR" || return 1
  check "$cookies" "/nonexistent" "CLAUDE_CHROME_COOKIES" || return 1
  return 0
}

test_provider_failure_reason() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=fail
  export AI_METER_TEST_REASON="rate-limited-by-test"
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_REASON
  check "$(jq -r '.meters[0].ok' <<<"$out")" "false" "ok" || return 1
  check "$(jq -r '.meters[0].reason' <<<"$out")" "rate-limited-by-test" "reason" || return 1
  check "$(jq '.meters[0].bars | length' <<<"$out")" "0" "bars empty" || return 1
  return 0
}

test_provider_invalid_json() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=invalid
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE
  check "$(jq -r '.meters[0].ok' <<<"$out")" "false" "ok" || return 1
  local reason; reason=$(jq -r '.meters[0].reason' <<<"$out")
  [ -n "$reason" ] && [ "$reason" != "null" ] || { ERR="empty reason"; return 1; }
  return 0
}

test_provider_timeout() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=timeout
  export AI_METER_TIMEOUT=2
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE
  export AI_METER_TIMEOUT=40
  check "$(jq -r '.meters[0].ok' <<<"$out")" "false" "ok" || return 1
  check "$(jq -r '.meters[0].reason' <<<"$out")" "timeout" "reason" || return 1
  return 0
}

test_last_good_fallback() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=ok
  "$MB" collect >/dev/null
  sleep 1
  export AI_METER_TEST_MODE=fail
  export AI_METER_TEST_REASON=oops
  local out; out=$("$MB" collect)
  unset AI_METER_TEST_MODE AI_METER_TEST_REASON
  check "$(jq -r '.meters[0].ok' <<<"$out")" "true" "ok" || return 1
  local age; age=$(jq -r '.meters[0].age' <<<"$out")
  [ "$age" -ge 1 ] || { ERR="age too small: $age"; return 1; }
  check "$(jq -r '.meters[0].reason' <<<"$out")" "oops" "reason" || return 1
  check "$(jq '.meters[0].bars | length' <<<"$out")" "3" "last-good bars kept" || return 1
  return 0
}

test_snapshot_cache_hit() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  "$MB" snapshot >/dev/null
  "$MB" snapshot >/dev/null
  unset AI_METER_TEST_MODE AI_METER_TEST_COUNTER
  local count; count=$(wc -l < "$d/counter.txt" 2>/dev/null || echo 0)
  check "$count" "1" "provider invocation count" || return 1
  return 0
}

test_snapshot_config_change_invalidates() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  "$MB" snapshot >/dev/null
  write_config "$d" '{"v":1,"meters":[{"id":"m1","type":"claude","label":"Claude Renamed","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  "$MB" snapshot >/dev/null
  unset AI_METER_TEST_MODE AI_METER_TEST_COUNTER
  local count; count=$(wc -l < "$d/counter.txt" 2>/dev/null || echo 0)
  check "$count" "2" "recollected after config change" || return 1
  return 0
}

test_snapshot_concurrent_single_collect() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  "$MB" snapshot >"$d/out1.json" &
  "$MB" snapshot >"$d/out2.json" &
  wait
  unset AI_METER_TEST_MODE AI_METER_TEST_COUNTER
  local count; count=$(wc -l < "$d/counter.txt" 2>/dev/null || echo 0)
  check "$count" "1" "provider invocation count" || return 1
  return 0
}

test_config_set_valid_b64() {
  local d; new_env; d="$ENV_DIR"
  local cfg='{"v":1,"meters":[{"id":"a1","type":"claude","label":"A","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  local b64; b64=$(printf '%s' "$cfg" | base64 -w0)
  "$MB" config set --b64 "$b64" >/dev/null || { ERR="config set exited nonzero"; return 1; }
  check "$(jq -c . "$d/config.json")" "$(jq -c . <<<"$cfg")" "stored config" || return 1
  return 0
}

test_config_set_stdin() {
  local d; new_env; d="$ENV_DIR"
  local cfg='{"v":1,"meters":[{"id":"b1","type":"codex","label":"B","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  printf '%s' "$cfg" | "$MB" config set || { ERR="config set exited nonzero"; return 1; }
  check "$(jq -c . "$d/config.json")" "$(jq -c . <<<"$cfg")" "stored config" || return 1
  return 0
}

test_config_set_rejects_invalid() {
  local d; new_env; d="$ENV_DIR"
  local good='{"v":1,"meters":[{"id":"keep-1","type":"claude","label":"Keep","sub":"","panel":true,"phone":true,"hide":[],"icon":"","opts":{}}]}'
  printf '%s' "$good" > "$d/config.json"
  chmod 600 "$d/config.json"
  local before; before=$(cat "$d/config.json")

  local cases=(
    'not json at all'
    '{"v":1,"meters":[{"id":"x1","type":"bogus"}]}'
    '{"v":1,"meters":[{"id":"dup","type":"claude"},{"id":"dup","type":"codex"}]}'
    '{"v":1,"meters":[{"id":"Bad ID!","type":"claude"}]}'
  )
  local i=0 c rc
  for c in "${cases[@]}"; do
    i=$((i + 1))
    printf '%s' "$c" | "$MB" config set >"$d/out.$i" 2>"$d/err.$i"
    rc=$?
    [ "$rc" -eq 2 ] || { ERR="case $i: expected exit 2 got $rc"; return 1; }
  done
  check "$(cat "$d/config.json")" "$before" "config unchanged" || return 1
  return 0
}

test_config_file_mode_0600() {
  local d; new_env; d="$ENV_DIR"
  printf '%s' '{"v":1,"meters":[]}' | "$MB" config set
  check "$(stat -c '%a' "$d/config.json")" "600" "config file mode" || return 1
  return 0
}

test_config_get_autodetect() {
  local d; new_env; d="$ENV_DIR"
  local fakehome; fakehome=$(mktemp -d "$WORKROOT/home.XXXXXX")
  mkdir -p "$fakehome/.claude" "$fakehome/.codex"
  echo '{}' > "$fakehome/.claude/.credentials.json"
  echo '{}' > "$fakehome/.codex/auth.json"
  rm -f "$d/config.json"
  local old_home="$HOME"
  export HOME="$fakehome"
  local out; out=$("$MB" config get)
  export HOME="$old_home"
  check "$(jq '.meters | length' <<<"$out")" "2" "meter count" || return 1
  check "$(jq -r '[.meters[].type] | sort | join(",")' <<<"$out")" "claude,codex" "types" || return 1
  return 0
}

test_config_init_writes_once() {
  local d; new_env; d="$ENV_DIR"
  rm -f "$d/config.json"
  local out1; out1=$("$MB" config init)
  local content1; content1=$(cat "$d/config.json")
  local out2; out2=$("$MB" config init)
  local content2; content2=$(cat "$d/config.json")
  check "$content2" "$content1" "content unchanged" || return 1
  check "$out2" "$out1" "output unchanged" || return 1
  return 0
}

test_fixture_hook() {
  local d; new_env; d="$ENV_DIR"
  local f="$d/fixture.json"
  echo '{"custom":"data"}' > "$f"
  export AI_METER_FIXTURE="$f"
  local out; out=$("$MB" snapshot)
  local out2; out2=$("$MB" collect)
  unset AI_METER_FIXTURE
  check "$out" '{"custom":"data"}' "snapshot fixture output" || return 1
  check "$out2" '{"custom":"data"}' "collect fixture output" || return 1
  [ ! -e "$d/state/snapshot.json" ] || { ERR="state written despite fixture"; return 1; }
  return 0
}

# ================= push =================

test_push_no_config_is_silent() {
  local d; new_env; d="$ENV_DIR"
  rm -f "$d/push.json"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_TOKEN_COUNT="$d/token-hits"
  export MB_CURL_SEND_COUNT="$d/send-hits"
  local out; out=$("$MB" push 2>"$d/stderr.txt")
  local rc=$?
  unset AI_METER_CURL MB_CURL_TOKEN_COUNT MB_CURL_SEND_COUNT
  check "$rc" "0" "exit code" || return 1
  [ -z "$out" ] || { ERR="stdout not empty: $out"; return 1; }
  [ ! -s "$d/stderr.txt" ] || { ERR="stderr not empty: $(cat "$d/stderr.txt")"; return 1; }
  [ ! -f "$d/token-hits" ] || { ERR="token endpoint hit"; return 1; }
  [ ! -f "$d/send-hits" ] || { ERR="send endpoint hit"; return 1; }
  return 0
}

test_push_jwt_signature_valid() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_TOKEN_ASSERTION="$d/assertion.txt"
  "$MB" push >/dev/null 2>"$d/stderr.txt"
  unset AI_METER_CURL MB_CURL_TOKEN_ASSERTION
  [ -s "$d/assertion.txt" ] || { ERR="no assertion captured: $(cat "$d/stderr.txt")"; return 1; }
  local jwt; jwt=$(cat "$d/assertion.txt")
  local h b s
  h=$(cut -d. -f1 <<<"$jwt"); b=$(cut -d. -f2 <<<"$jwt"); s=$(cut -d. -f3 <<<"$jwt")
  local claims; claims=$(decode_b64url "$b")
  check "$(jq -r '.iss' <<<"$claims")" "svc@example-project.iam.gserviceaccount.com" "iss" || return 1
  check "$(jq -r '.scope' <<<"$claims")" \
    "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email" \
    "scope" || return 1
  check "$(jq -r '.aud' <<<"$claims")" "https://oauth2.example.test/token" "aud" || return 1
  local iat exp; iat=$(jq -r '.iat' <<<"$claims"); exp=$(jq -r '.exp' <<<"$claims")
  [ "$((exp - iat))" -eq 3600 ] || { ERR="exp-iat != 3600 (iat=$iat exp=$exp)"; return 1; }

  local sig_std pad
  sig_std=$(printf '%s' "$s" | tr '_-' '/+')
  pad=$(( (4 - ${#sig_std} % 4) % 4 ))
  [ "$pad" -gt 0 ] && sig_std="$sig_std$(printf '=%.0s' $(seq 1 "$pad"))"
  printf '%s' "$sig_std" | base64 -d > "$d/sig.bin" 2>/dev/null
  if ! printf '%s.%s' "$h" "$b" | openssl dgst -sha256 -verify "$d/key.pub.pem" -signature "$d/sig.bin" >"$d/verify.out" 2>&1; then
    ERR="signature verify failed: $(cat "$d/verify.out")"
    return 1
  fi
  return 0
}

test_push_token_cached() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_TOKEN_COUNT="$d/token-hits"
  "$MB" push --force >/dev/null 2>&1
  "$MB" push --force >/dev/null 2>&1
  unset AI_METER_CURL MB_CURL_TOKEN_COUNT
  local count; count=$(wc -l < "$d/token-hits" 2>/dev/null || echo 0)
  check "$count" "1" "token endpoint hits" || return 1
  return 0
}

test_push_message_shape() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" '{"v":1,"meters":[
    {"id":"m1","type":"claude","label":"Claude","sub":"Home","panel":true,"phone":true,"hide":[],"icon":"","opts":{}},
    {"id":"m2","type":"codex","label":"Codex","sub":"","panel":true,"phone":false,"hide":[],"icon":"","opts":{}}
  ]}'
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "mytopic"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SEND_BODY="$d/send-body.json"
  "$MB" push --force >/dev/null 2>"$d/stderr.txt"
  unset AI_METER_CURL MB_CURL_SEND_BODY
  [ -s "$d/send-body.json" ] || { ERR="no send body captured: $(cat "$d/stderr.txt")"; return 1; }
  local body; body=$(cat "$d/send-body.json")
  check "$(jq -r '.message.topic' <<<"$body")" "mytopic" "topic" || return 1
  check "$(jq -r '.message.android.priority' <<<"$body")" "high" "priority" || return 1
  check "$(jq -r '.message.android.ttl' <<<"$body")" "900s" "ttl" || return 1
  check "$(jq -r '.message.android.collapse_key' <<<"$body")" "meters" "collapse_key" || return 1
  local p_str; p_str=$(jq -r '.message.data.p' <<<"$body")
  printf '%s' "$p_str" | jq -e . >/dev/null 2>&1 || { ERR="data.p not valid JSON"; return 1; }
  check "$(printf '%s' "$p_str" | jq '.meters | length')" "1" "phone-only meter count" || return 1
  check "$(printf '%s' "$p_str" | jq -r '.meters[0].id')" "m1" "phone meter id" || return 1
  check "$(printf '%s' "$p_str" | jq -r '.meters[0] | keys | sort | join(",")')" \
    "age,bars,id,label,ok,plan,reason,source,sub,type" "meter field set" || return 1
  return 0
}

test_push_skips_unchanged() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SEND_COUNT="$d/send-hits"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":10,"reset_in":100},"seven":{"pct":20,"reset_in":200},"model":null}'
  "$MB" push >/dev/null 2>"$d/first.err"
  "$MB" push >/dev/null 2>"$d/second.err"
  unset AI_METER_CURL MB_CURL_SEND_COUNT AI_METER_TEST_MODE AI_METER_TEST_OUT
  local count; count=$(wc -l < "$d/send-hits" 2>/dev/null || echo 0)
  check "$count" "1" "send hits" || return 1
  grep -q "skipped (unchanged)" "$d/second.err" || { ERR="stderr: $(cat "$d/second.err")"; return 1; }
  return 0
}

test_push_sends_on_change() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SEND_COUNT="$d/send-hits"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":10,"reset_in":100},"seven":{"pct":20,"reset_in":200},"model":null}'
  "$MB" push >/dev/null 2>&1
  rm -f "$d/state/snapshot.json" "$d/state/snapshot.meta.json"
  export AI_METER_TEST_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":55,"reset_in":100},"seven":{"pct":20,"reset_in":200},"model":null}'
  "$MB" push >/dev/null 2>"$d/second.err"
  unset AI_METER_CURL MB_CURL_SEND_COUNT AI_METER_TEST_MODE AI_METER_TEST_OUT
  local count; count=$(wc -l < "$d/send-hits" 2>/dev/null || echo 0)
  check "$count" "2" "send hits" || return 1
  grep -q "sent (changed)" "$d/second.err" || { ERR="stderr: $(cat "$d/second.err")"; return 1; }
  return 0
}

test_push_force() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SEND_COUNT="$d/send-hits"
  "$MB" push >/dev/null 2>&1
  "$MB" push --force >/dev/null 2>"$d/second.err"
  unset AI_METER_CURL MB_CURL_SEND_COUNT
  local count; count=$(wc -l < "$d/send-hits" 2>/dev/null || echo 0)
  check "$count" "2" "send hits" || return 1
  grep -q "sent (forced)" "$d/second.err" || { ERR="stderr: $(cat "$d/second.err")"; return 1; }
  return 0
}

test_push_heartbeat_after_900s() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SEND_COUNT="$d/send-hits"
  "$MB" push >/dev/null 2>&1
  local state old_payload past
  state=$(cat "$d/state/push-state.json")
  old_payload=$(jq -c '.payload' <<<"$state")
  past=$(( $(date +%s) - 901 ))
  jq -n --argjson sent_at "$past" --argjson payload "$old_payload" '{sent_at: $sent_at, payload: $payload}' \
    > "$d/state/push-state.json"
  "$MB" push >/dev/null 2>"$d/second.err"
  unset AI_METER_CURL MB_CURL_SEND_COUNT
  local count; count=$(wc -l < "$d/send-hits" 2>/dev/null || echo 0)
  check "$count" "2" "send hits" || return 1
  grep -q "sent (heartbeat)" "$d/second.err" || { ERR="stderr: $(cat "$d/second.err")"; return 1; }
  return 0
}

test_push_payload_too_large() {
  local d; new_env; d="$ENV_DIR"
  local biglabel; biglabel=$(printf 'x%.0s' $(seq 1 4000))
  local cfg; cfg=$(jq -n --arg lbl "$biglabel" \
    '{v:1, meters:[{id:"m1",type:"claude",label:$lbl,sub:"",panel:true,phone:true,hide:[],icon:"",opts:{}}]}')
  printf '%s' "$cfg" > "$d/config.json"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SEND_COUNT="$d/send-hits"
  local errout; errout=$("$MB" push 2>&1 >/dev/null)
  local rc=$?
  unset AI_METER_CURL MB_CURL_SEND_COUNT
  [ "$rc" -ne 0 ] || { ERR="expected nonzero exit"; return 1; }
  [ ! -f "$d/send-hits" ] || { ERR="send endpoint was hit"; return 1; }
  printf '%s' "$errout" | grep -qi "too large" || { ERR="stderr: $errout"; return 1; }
  return 0
}

# ================= listen =================

test_listen_not_configured_exits_0() {
  local d; new_env; d="$ENV_DIR"
  rm -f "$d/push.json"
  local out; out=$("$MB" listen 2>"$d/stderr.txt")
  local rc=$?
  check "$rc" "0" "exit code" || return 1
  [ -z "$out" ] || { ERR="stdout not empty: $out"; return 1; }
  [ -s "$d/stderr.txt" ] || { ERR="expected one stderr line"; return 1; }
  return 0
}

test_listen_ignores_initial_stale_event() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "aaaa1111aaaa1111aaaa1111aaaa1111"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  local now_ms=2000000000000
  sse_event "$(( now_ms - 200000 ))" > "$ssedir/1"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SSE_DIR="$ssedir"
  export MB_CURL_SSE_CONNECT_COUNT="$d/sse-connects"
  export AI_METER_LISTEN_MAX_CONNECTS=1
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS="$now_ms"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  export MB_CURL_SEND_COUNT="$d/send-hits"

  "$MB" listen >/dev/null 2>"$d/stderr.txt"
  local rc=$?
  unset AI_METER_CURL MB_CURL_SSE_DIR MB_CURL_SSE_CONNECT_COUNT AI_METER_LISTEN_MAX_CONNECTS \
    AI_METER_RECONNECT_DELAY AI_METER_NOW_MS AI_METER_TEST_MODE AI_METER_TEST_COUNTER MB_CURL_SEND_COUNT

  check "$rc" "0" "exit code" || return 1
  [ ! -f "$d/counter.txt" ] || { ERR="collect ran on stale event"; return 1; }
  [ ! -f "$d/send-hits" ] || { ERR="push sent on stale event"; return 1; }
  grep -q "ignored stale" "$d/stderr.txt" || { ERR="stderr: $(cat "$d/stderr.txt")"; return 1; }
  return 0
}

test_listen_handles_new_request() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "bbbb2222bbbb2222bbbb2222bbbb2222"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  local now_ms=2000000000000
  sse_event "$(( now_ms - 1000 ))" > "$ssedir/1"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SSE_DIR="$ssedir"
  export MB_CURL_SSE_CONNECT_COUNT="$d/sse-connects"
  export AI_METER_LISTEN_MAX_CONNECTS=1
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS="$now_ms"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  export MB_CURL_SEND_COUNT="$d/send-hits"

  "$MB" listen >/dev/null 2>"$d/stderr.txt"
  local rc=$?
  unset AI_METER_CURL MB_CURL_SSE_DIR MB_CURL_SSE_CONNECT_COUNT AI_METER_LISTEN_MAX_CONNECTS \
    AI_METER_RECONNECT_DELAY AI_METER_NOW_MS AI_METER_TEST_MODE AI_METER_TEST_COUNTER MB_CURL_SEND_COUNT

  check "$rc" "0" "exit code" || return 1
  [ -f "$d/counter.txt" ] || { ERR="collect did not run: $(cat "$d/stderr.txt")"; return 1; }
  [ -f "$d/send-hits" ] || { ERR="push did not send: $(cat "$d/stderr.txt")"; return 1; }
  grep -q "handled refresh request" "$d/stderr.txt" || { ERR="stderr: $(cat "$d/stderr.txt")"; return 1; }
  return 0
}

test_listen_honours_recent_request_on_connect() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "cccc3333cccc3333cccc3333cccc3333"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  local now_ms=2000000000000
  sse_event "$(( now_ms - 500000 ))" > "$ssedir/1"
  sse_event "$(( now_ms - 2000 ))" > "$ssedir/2"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SSE_DIR="$ssedir"
  export MB_CURL_SSE_CONNECT_COUNT="$d/sse-connects"
  export AI_METER_LISTEN_MAX_CONNECTS=2
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS="$now_ms"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  export MB_CURL_SEND_COUNT="$d/send-hits"

  "$MB" listen >/dev/null 2>"$d/stderr.txt"
  unset AI_METER_CURL MB_CURL_SSE_DIR MB_CURL_SSE_CONNECT_COUNT AI_METER_LISTEN_MAX_CONNECTS \
    AI_METER_RECONNECT_DELAY AI_METER_NOW_MS AI_METER_TEST_MODE AI_METER_TEST_COUNTER MB_CURL_SEND_COUNT

  local count; count=$(wc -l < "$d/counter.txt" 2>/dev/null || echo 0)
  check "$count" "1" "collect ran only for the recent event" || return 1
  grep -q "ignored stale" "$d/stderr.txt" || { ERR="missing stale log: $(cat "$d/stderr.txt")"; return 1; }
  grep -q "handled refresh request" "$d/stderr.txt" || { ERR="missing handled log: $(cat "$d/stderr.txt")"; return 1; }
  return 0
}

test_listen_rate_limits_within_10s() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "dddd4444dddd4444dddd4444dddd4444"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  local now_ms=2000000000000
  local val1=$(( now_ms - 3000 )) val2=$(( now_ms - 1000 ))
  { sse_event "$val1"; sse_event "$val2"; } > "$ssedir/1"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SSE_DIR="$ssedir"
  export AI_METER_LISTEN_MAX_CONNECTS=1
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS="$now_ms"
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"
  export MB_CURL_SEND_COUNT="$d/send-hits"

  "$MB" listen >/dev/null 2>"$d/stderr.txt"
  unset AI_METER_CURL MB_CURL_SSE_DIR AI_METER_LISTEN_MAX_CONNECTS AI_METER_RECONNECT_DELAY \
    AI_METER_NOW_MS AI_METER_TEST_MODE AI_METER_TEST_COUNTER MB_CURL_SEND_COUNT

  local count; count=$(wc -l < "$d/counter.txt" 2>/dev/null || echo 0)
  check "$count" "1" "collect ran once, second event rate-limited" || return 1
  grep -q "rate-limited" "$d/stderr.txt" || { ERR="stderr: $(cat "$d/stderr.txt")"; return 1; }
  check "$(cat "$d/state/refresh-last")" "$val2" "refresh-last records the skipped value too" || return 1
  return 0
}

test_listen_reconnects_after_auth_revoked() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "eeee5555eeee5555eeee5555eeee5555"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  printf 'event: auth_revoked\ndata: null\n\n' > "$ssedir/1"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SSE_DIR="$ssedir"
  export MB_CURL_SSE_CONNECT_COUNT="$d/sse-connects"
  export AI_METER_LISTEN_MAX_CONNECTS=2
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS=2000000000000

  "$MB" listen >/dev/null 2>"$d/stderr.txt"
  local rc=$?
  unset AI_METER_CURL MB_CURL_SSE_DIR MB_CURL_SSE_CONNECT_COUNT AI_METER_LISTEN_MAX_CONNECTS \
    AI_METER_RECONNECT_DELAY AI_METER_NOW_MS

  check "$rc" "0" "exit code" || return 1
  local count; count=$(wc -l < "$d/sse-connects" 2>/dev/null || echo 0)
  check "$count" "2" "two SSE connections" || return 1
  return 0
}

test_listen_ignores_keepalive() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "ffff6666ffff6666ffff6666ffff6666"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  printf 'event: keep-alive\ndata: null\n\n' > "$ssedir/1"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_SSE_DIR="$ssedir"
  export AI_METER_LISTEN_MAX_CONNECTS=1
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS=2000000000000
  export AI_METER_TEST_MODE=ok
  export AI_METER_TEST_COUNTER="$d/counter.txt"

  "$MB" listen >/dev/null 2>"$d/stderr.txt"
  unset AI_METER_CURL MB_CURL_SSE_DIR AI_METER_LISTEN_MAX_CONNECTS AI_METER_RECONNECT_DELAY \
    AI_METER_NOW_MS AI_METER_TEST_MODE AI_METER_TEST_COUNTER

  [ ! -f "$d/counter.txt" ] || { ERR="collect ran on keep-alive"; return 1; }
  return 0
}

test_token_scopes_include_database() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  write_push_config "$d" "$d/sa.json" "meters"
  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_TOKEN_ASSERTION="$d/assertion.txt"
  "$MB" push --force >/dev/null 2>"$d/stderr.txt"
  unset AI_METER_CURL MB_CURL_TOKEN_ASSERTION
  [ -s "$d/assertion.txt" ] || { ERR="no assertion captured: $(cat "$d/stderr.txt")"; return 1; }
  local jwt b claims
  jwt=$(cat "$d/assertion.txt")
  b=$(cut -d. -f2 <<<"$jwt")
  claims=$(decode_b64url "$b")
  check "$(jq -r '.scope' <<<"$claims")" \
    "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email" \
    "scope" || return 1
  return 0
}

test_secrets_not_in_argv() {
  local d; new_env; d="$ENV_DIR"
  write_config "$d" "$CLAUDE_CFG"
  make_service_account "$d"
  local refresh_key="c0ffee00c0ffee00c0ffee00c0ffee00"
  write_listen_push_config "$d" "$d/sa.json" "meters" "https://example-db.firebaseio.com" "$refresh_key"

  export AI_METER_CURL="$CURL_STUB"
  export MB_CURL_ARGV_LOG="$d/argv.log"
  export MB_CURL_ACCESS_TOKEN="SUPERSECRETACCESSTOKEN99"
  "$MB" push --force >/dev/null 2>"$d/push.err"

  local ssedir="$d/sse"; mkdir -p "$ssedir"
  local now_ms=2000000000000
  sse_event "$(( now_ms - 1000 ))" > "$ssedir/1"
  export MB_CURL_SSE_DIR="$ssedir"
  export AI_METER_LISTEN_MAX_CONNECTS=1
  export AI_METER_RECONNECT_DELAY=0
  export AI_METER_NOW_MS="$now_ms"
  export AI_METER_TEST_MODE=ok
  "$MB" listen >/dev/null 2>"$d/listen.err"

  unset AI_METER_CURL MB_CURL_ARGV_LOG MB_CURL_ACCESS_TOKEN MB_CURL_SSE_DIR AI_METER_LISTEN_MAX_CONNECTS \
    AI_METER_RECONNECT_DELAY AI_METER_NOW_MS AI_METER_TEST_MODE

  [ -s "$d/argv.log" ] || { ERR="no argv captured"; return 1; }
  grep -qF "SUPERSECRETACCESSTOKEN99" "$d/argv.log" && { ERR="access token leaked into argv"; return 1; }
  grep -qF "$refresh_key" "$d/argv.log" && { ERR="refresh key leaked into argv"; return 1; }
  grep -qF "assertion=" "$d/argv.log" && { ERR="jwt assertion leaked into argv"; return 1; }
  grep -qiF "bearer" "$d/argv.log" && { ERR="bearer header leaked into argv"; return 1; }
  return 0
}

# ================= run =================

run mapping_claude test_mapping_claude
run mapping_codex test_mapping_codex
run mapping_grok test_mapping_grok
run mapping_cursor test_mapping_cursor
run hide_drops_bars test_hide_drops_bars
run sub_empty_is_null test_sub_empty_is_null
run order_follows_config test_order_follows_config
run claude_isolated_account_disables_browser test_claude_isolated_account_disables_browser
run provider_failure_reason test_provider_failure_reason
run provider_invalid_json test_provider_invalid_json
run provider_timeout test_provider_timeout
run last_good_fallback test_last_good_fallback
run snapshot_cache_hit test_snapshot_cache_hit
run snapshot_config_change_invalidates test_snapshot_config_change_invalidates
run snapshot_concurrent_single_collect test_snapshot_concurrent_single_collect
run config_set_valid_b64 test_config_set_valid_b64
run config_set_stdin test_config_set_stdin
run config_set_rejects_invalid test_config_set_rejects_invalid
run config_file_mode_0600 test_config_file_mode_0600
run config_get_autodetect test_config_get_autodetect
run config_init_writes_once test_config_init_writes_once
run fixture_hook test_fixture_hook
run push_no_config_is_silent test_push_no_config_is_silent
run push_jwt_signature_valid test_push_jwt_signature_valid
run push_token_cached test_push_token_cached
run push_message_shape test_push_message_shape
run push_skips_unchanged test_push_skips_unchanged
run push_sends_on_change test_push_sends_on_change
run push_force test_push_force
run push_heartbeat_after_900s test_push_heartbeat_after_900s
run push_payload_too_large test_push_payload_too_large

run listen_not_configured_exits_0 test_listen_not_configured_exits_0
run listen_ignores_initial_stale_event test_listen_ignores_initial_stale_event
run listen_handles_new_request test_listen_handles_new_request
run listen_honours_recent_request_on_connect test_listen_honours_recent_request_on_connect
run listen_rate_limits_within_10s test_listen_rate_limits_within_10s
run listen_reconnects_after_auth_revoked test_listen_reconnects_after_auth_revoked
run listen_ignores_keepalive test_listen_ignores_keepalive
run token_scopes_include_database test_token_scopes_include_database
run secrets_not_in_argv test_secrets_not_in_argv

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
[ "$FAIL_COUNT" -eq 0 ]
