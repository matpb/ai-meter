#!/usr/bin/env bash
# codex-meter — emit current OpenAI Codex usage as one JSON line.
# Sources, fallback and env overrides: see docs/providers.md.

set -f
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH:/home/linuxbrew/.linuxbrew/bin"

codex_home="${CODEX_HOME:-$HOME/.codex}"
auth="$codex_home/auth.json"
now=$(date +%s)
USAGE_URL="https://chatgpt.com/backend-api/codex/usage"
UA="codex_cli_rs/0.144.4"

log() { [ -n "${CODEX_METER_DEBUG:-}" ] && printf 'codex-meter: %s\n' "$*" >&2; }

# ---------- fallback: newest session rollout ----------
# Shape differs from the HTTP one: primary/secondary rather than *_window (see docs/providers.md).
emit_rollout() {
    local f
    f=$(find "$codex_home/sessions" -name 'rollout-*.jsonl' -type f -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$f" ] && [ -s "$f" ] || { printf '{"ok":false,"reason":"no-data"}\n'; return; }

    local line
    line=$(grep '"rate_limits"' "$f" 2>/dev/null | tail -1)
    [ -n "$line" ] || { printf '{"ok":false,"reason":"no-data"}\n'; return; }

    printf '%s' "$line" | jq -e -c --argjson now "$now" '
      def toepoch: (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601);
      def win(w):
        (w.resets_at) as $r | ((w.used_percent // 0)) as $p
        | (if $r == null then null else ($r - $now) end) as $ri
        | { pct:      (if ($r != null and $r <= $now) then 0 else $p end),
            reset_in: (if $ri == null then null elif $ri < 0 then 0 else $ri end),
            fresh:    false };
      .payload.rate_limits as $rl
      | { ok: true, source: "rollout",
          age: ($now - (.timestamp | toepoch)),
          plan: ($rl.plan_type // ""), credits: ($rl.credits.balance // ""),
          five: win($rl.primary), seven: win($rl.secondary) }
    ' 2>/dev/null || printf '{"ok":false,"reason":"parse-error"}\n'
}

# ---------- is the stored access token still valid? ----------
# ~10-day JWT life; decoding `exp` skips a doomed round-trip instead of failing on a 401.
token_alive() {
    local payload pad exp
    payload=$(printf '%s' "$1" | cut -d. -f2)
    pad=$(( (4 - ${#payload} % 4) % 4 ))
    [ "$pad" -gt 0 ] && payload="$payload$(printf '=%.0s' $(seq 1 $pad))"
    exp=$(printf '%s' "$payload" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
    [ -n "$exp" ] || return 0   # cannot tell — let the request decide
    [ "$exp" -gt "$now" ]
}

# ---------- primary: live usage endpoint ----------
try_live() {
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        || { log "missing a dependency (curl/jq)"; return 1; }
    [ -s "$auth" ] || { log "no $auth — run: codex login"; return 1; }

    local tok acct resp
    tok=$(jq -r '.tokens.access_token // empty' "$auth" 2>/dev/null)
    acct=$(jq -r '.tokens.account_id // empty' "$auth" 2>/dev/null)
    [ -n "$tok" ] || { log "no access token in auth.json"; return 1; }
    token_alive "$tok" || { log "access token expired — run codex once to refresh it"; return 1; }

    resp=$(timeout 10 curl -sS --fail --max-time 10 "$USAGE_URL" \
        -H "Authorization: Bearer $tok" \
        ${acct:+-H "chatgpt-account-id: $acct"} \
        -H "User-Agent: $UA" 2>/dev/null)
    [ -n "$resp" ] || { log "usage endpoint returned nothing"; return 1; }

    printf '%s' "$resp" | jq -e -c --argjson now "$now" '
      def win(w):
        { pct:      (w.used_percent // 0),
          reset_in: (if w.reset_at == null then null
                     elif (w.reset_at - $now) < 0 then 0
                     else (w.reset_at - $now) end),
          # A window nobody has touched reports 0% with the full duration still to run. Saying
          # "unused" beats saying "0%", which reads like a suspiciously good week.
          fresh:    (((w.used_percent // 0) == 0)
                     and ((w.reset_after_seconds // 0) >= ((w.limit_window_seconds // 0) - 1))) };
      if (.rate_limit.primary_window == null) then error("no windows") else . end
      | { ok: true, source: "live", age: 0,
          plan: (.plan_type // ""), credits: (.credits.balance // ""),
          five: win(.rate_limit.primary_window), seven: win(.rate_limit.secondary_window) }
    ' 2>/dev/null || { log "could not parse usage response"; return 1; }
}

if out=$(try_live) && [ -n "$out" ]; then
    printf '%s\n' "$out"
else
    emit_rollout
fi
