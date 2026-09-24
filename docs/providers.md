# Providers

Each provider script is invoked as `bash providers/<type>.sh` and prints one line of JSON to stdout.
`ai-meter` sets the env vars documented per-provider below (from a meter's `opts`) for that single
invocation, reads stdout, and maps the result onto snapshot bars: see `docs/contract.md` for the bar
mapping table. This file documents what each script actually reads and how it falls back.

## claude.sh

Reads current Claude subscription usage.

- **First source**: Claude Code's own OAuth token (`~/.claude/.credentials.json`) against
  `api.anthropic.com`.
- **Next source**: the claude.ai usage endpoint. Always fresh, account-wide (counts phone, web and
  other machines) and free (a read endpoint). Auth is your claude.ai web session cookie, decrypted on
  the fly from a Chromium-family browser's cookie store using the browser's "Safe Storage" key held in
  KWallet (or Secret Service / gnome-keyring). The cookie is used in memory only: never written to
  disk, never logged, only ever sent to claude.ai over HTTPS.
- **Fallback**: an optional snapshot a Claude Code statusline can cache at
  `~/.claude/usage/.ratelimit.json`. Used when the live fetch can't run (browser logged out, wallet
  locked, offline). `age` reflects how old that snapshot is when used.

Env overrides (all optional):

| Var | Meaning |
|---|---|
| `CLAUDE_ORG_ID` | claude.ai organization UUID (else auto-detected by "chat" capability) |
| `CLAUDE_CHROME_COOKIES` | path to a Chromium `Cookies` SQLite DB (else common Chrome/Chromium/Brave paths) |
| `CLAUDE_USAGE_DIR` | dir holding the statusline fallback snapshot (default `~/.claude/usage`) |
| `CLAUDE_METER_DEBUG=1` | print diagnostics to stderr |

`claude.sh --list-profiles` lists discoverable Chromium cookie DBs as a JSON array of
`{"path","label"}`, for a config UI to offer as `opts.cookiesPath` choices.

Output shape:

```json
{"ok":true,"source":"token"|"live"|"cache","age":0,
 "five":{"pct":9,"reset_in":3600},"seven":{"pct":40,"reset_in":86400},
 "model":{"name":"Fable","pct":12,"reset_in":86400}}
```

or `{"ok":false,"reason":"..."}`. `model` is the per-model weekly window (currently the one model
with `kind == "weekly_scoped"`); `null` in the cache fallback, since that snapshot doesn't carry it.

## codex.sh

Reads current OpenAI Codex usage.

- **Primary**: the ChatGPT usage endpoint. Always fresh, account-wide (Codex CLI, ChatGPT desktop app,
  Codex Cloud) and free (a read endpoint). Auth is the OAuth bearer token the Codex CLI stores in
  `~/.codex/auth.json` after `codex login`: no browser, no cookie decryption, no keyring.
- **Fallback**: the newest session rollout at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Codex
  writes a `rate_limits` block there on every turn, via a `token_count` event, so this needs no setup.
  Its shape differs from the HTTP one (`primary`/`secondary` instead of `*_window`, `window_minutes`
  instead of `limit_window_seconds`). `age` reflects how old that reading is when used.

The stored access token is a JWT with roughly a 10-day life; the script decodes its `exp` claim to
skip a doomed round-trip and fall back deliberately, rather than fail on a 401.

Env overrides:

| Var | Meaning |
|---|---|
| `CODEX_HOME` | Codex config dir (default `~/.codex`) |
| `CODEX_METER_DEBUG=1` | print diagnostics to stderr |

Output shape:

```json
{"ok":true,"source":"live"|"rollout","age":0,"plan":"plus","credits":"0",
 "five":{"pct":9,"reset_in":3600,"fresh":false},"seven":{"pct":40,"reset_in":86400,"fresh":false}}
```

or `{"ok":false,"reason":"..."}"`. `fresh` marks a window that hasn't started being used yet (0%
used with the full window duration still ahead), so a view can say "unused" rather than "0%".

## grok.sh

Reads the SuperGrok weekly credit pool and the Grok Build share.

- **Primary**: `cli-chat-proxy.grok.com` billing + settings endpoints. Auth is the token xAI's CLI
  stores in `~/.grok/auth.json` after login. Token is used in memory only, sent only to
  `cli-chat-proxy.grok.com` over HTTPS.
- **Fallback**: the last successful live read, cached at `~/.config/grok-meter/last.json`.

Env overrides:

| Var | Meaning |
|---|---|
| `GROK_HOME` | Grok CLI config dir (default `~/.grok`) |
| `GROK_METER_CACHE` | cache snapshot path (default `~/.config/grok-meter/last.json`) |
| `GROK_METER_BILLING_JSON` / `GROK_METER_SETTINGS_JSON` | test fixtures, bypass the live calls |
| `GROK_METER_DEBUG=1` | print diagnostics to stderr |

Output shape:

```json
{"ok":true,"source":"live"|"cache","age":0,"plan":"SuperGrok",
 "five":{"pct":9,"reset_in":3600,"fresh":false},"seven":{"pct":40,"reset_in":604800,"fresh":false}}
```

or `{"ok":false,"reason":"..."}`. `five` is the Grok Build share, `seven` is the weekly credit pool.

## cursor.sh

Reads current Cursor plan usage.

- **Primary**: Cursor's dashboard Connect-RPC API on `api2.cursor.sh`. Always fresh, account-wide (the
  IDE, the CLI, Cloud Agents) and free (read-only status). Auth is the access token Cursor already
  stores after sign-in: `~/.config/cursor/auth.json` from the CLI, or `cursorAuth/accessToken` in the
  IDE's state DB. Token used in memory only.
- **Fallback**: the last successful live read, cached at `~/.config/cursor-meter/last.json`.

There is also a legacy request-bucket shape (`normalize_legacy`) for accounts whose usage endpoint
doesn't return `planUsage` (older Enterprise-style plans), read from `<api_base>/auth/usage`.

Env overrides:

| Var | Meaning |
|---|---|
| `CURSOR_CONFIG_HOME` | CLI auth dir (default `~/.config/cursor`) |
| `CURSOR_STATE_DB` | IDE state DB (default `~/.config/Cursor/User/globalStorage/state.vscdb`) |
| `CURSOR_METER_CACHE` | cache snapshot path (default `~/.config/cursor-meter/last.json`) |
| `CURSOR_METER_USAGE_JSON` / `CURSOR_METER_PLAN_JSON` / `CURSOR_METER_SAND_JSON` | test fixtures |
| `CURSOR_METER_DEBUG=1` | print diagnostics to stderr |

Output shape:

```json
{"ok":true,"source":"live"|"cache","age":0,"plan":"Pro","cycle_sec":2592000,"total_pct":20,
 "five":{"pct":9,"reset_in":900000,"fresh":false},
 "seven":{"pct":40,"reset_in":900000,"fresh":false},
 "grok":{"pct":5,"reset_in":86400,"fresh":false,"week_sec":604800}}
```

or `{"ok":false,"reason":"..."}"`. `five` = monthly Models pool, `seven` = monthly Other Models
pool, `grok` = Grok Bot weekly usage (`null` when the account has no Grok Bot allocation).
