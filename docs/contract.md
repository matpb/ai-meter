# AI Meter contracts

One collector fetches every AI subscription meter. Every view (the Plasma widget, the Android
widget) reads what the collector produced and never calls a provider itself.

```
providers/*.sh ──► ai-meter (collector, flock + max-age cache) ──► snapshot.json
                                                 │                      ├─► Plasma widget (runs `ai-meter snapshot`)
                                                 └─► ai-meter push ───┴─► FCM topic ──► Android widget
```

## Paths

| What | Default | Override |
|---|---|---|
| Config | `${XDG_CONFIG_HOME:-~/.config}/ai-meter/config.json` | `AI_METER_CONFIG` |
| Push config | `${XDG_CONFIG_HOME:-~/.config}/ai-meter/push.json` | `AI_METER_PUSH_CONFIG` |
| State dir | `${XDG_STATE_HOME:-~/.local/state}/ai-meter/` | `AI_METER_STATE` |
| Snapshot | `<state>/snapshot.json` | |
| Providers dir | `<collector dir>/providers` | `AI_METER_PROVIDERS` |

## config.json (v1)

```json
{
  "v": 1,
  "meters": [
    {
      "id": "claude-1",
      "type": "claude",
      "label": "Claude",
      "sub": "Personal",
      "panel": true,
      "phone": true,
      "hide": ["model"],
      "icon": "",
      "opts": { "claudeDir": "", "cookiesPath": "" }
    }
  ]
}
```

- `id`: unique, `[a-z0-9-]+`. `type`: `claude` | `codex` | `grok` | `cursor`.
- `label`, `sub`: display strings. `sub` may be `""` (rendered as absent).
- `panel`: show this meter in the Plasma panel. When no meter has `panel: true`, the panel shows the AI Meter icon only.
- `phone`: include this meter in the FCM push.
- `hide`: bar keys dropped from the snapshot (both views). Unknown keys are ignored.
- `icon`: optional absolute path to an SVG/PNG replacing the provider icon (to tell two accounts apart). `""` = provider default.
- `opts` per type, all optional, `""` = provider default:
  - claude: `claudeDir` (Claude Code config dir, default `~/.claude`) → `CLAUDE_USAGE_DIR=<claudeDir>/usage`; `cookiesPath` (Chromium Cookies DB) → `CLAUDE_CHROME_COOKIES`. When `claudeDir` is set and `cookiesPath` is empty, the collector sets `CLAUDE_CHROME_COOKIES=/nonexistent` so the browser rung can never read a different account's cookie.
  - codex: `codexHome` → `CODEX_HOME`.
  - grok: `grokHome` → `GROK_HOME`.
  - cursor: none.
- Missing config file: `ai-meter snapshot` behaves as if `ai-meter config init` had produced it (auto-detect: `~/.claude/.credentials.json` or any Chromium profile → claude; `~/.codex/auth.json` → codex; `~/.grok` → grok; `~/.config/cursor/auth.json` or the Cursor IDE state DB → cursor). Detected meters get `panel: true, phone: true, hide: ["model"]`.

## Bar keys per type

| type | provider JSON | bar `k` | default `label` | window `win` (s) |
|---|---|---|---|---|
| claude | `five` | `5h` | `5h` | 18000 |
| claude | `seven` | `7d` | `7d` | 604800 |
| claude | `model` (may be null) | `model` | `model.name` (e.g. "Fable") | 604800 |
| codex | `five` / `seven` | `5h` / `7d` | same | 18000 / 604800 |
| grok | `five` / `seven` | `cli` / `7d` | `CLI` / `7d` | 604800 / 604800 |
| cursor | `five` / `seven` | `models` / `other` | `Models` / `Other` | `cycle_sec // 2592000` |
| cursor | `grok` (may be null) | `grok` | `Grok` | `grok.week_sec // 604800` |

A bar whose source object is null is omitted.

## snapshot.json (v2)

```json
{
  "v": 2,
  "ts": 1790270278,
  "meters": [
    {
      "id": "claude-1", "type": "claude", "label": "Claude", "sub": "Personal",
      "panel": true, "phone": true, "icon": "",
      "ok": true, "source": "token", "age": 0, "plan": null, "reason": null,
      "bars": [
        { "k": "5h", "label": "5h", "pct": 9, "reset_at": 1790282399, "fresh": false, "win": 18000 }
      ]
    }
  ]
}
```

- `ts`: epoch seconds when collected. `reset_at`: absolute epoch (`ts + reset_in`), null if unknown. `pct`: integer 0..100 (rounded), null if unknown.
- `ok: false` → `reason` string, `bars: []`, unless a last-good reading exists: then the last-good bars are served with `ok: true`, `age` grown by the time since that reading, and `reason` set to the current failure.
- `sub: ""` in config → `null` here.
- Order = config order.

## CLI (`ai-meter`)

| Command | Behaviour | stdout |
|---|---|---|
| `snapshot [--max-age N]` | Return `<state>/snapshot.json` if younger than N s (default 60) and collected from the current config; else collect under an exclusive `flock`, re-checking freshness after the lock is acquired. | snapshot JSON, one line |
| `collect` | Collect now, ignore age. | snapshot JSON |
| `push [--force]` | Exit 0 silently if no push config. Else `snapshot --max-age 60`, then send via FCM when changed, forced, or 900 s since the last send. | one status line on stderr |
| `config get` | Print the config (auto-detected one if no file; not written). | config JSON |
| `config set` | Read config JSON from stdin, or from `--b64 <base64>`. Validate, write atomically (0600). Exit 2 on invalid. | nothing |
| `config init` | Write the auto-detected config if no file exists. | config JSON |
| `profiles` | Proxy `providers/claude.sh --list-profiles`. | `[{"path","label"}]` |

Test hook: `AI_METER_FIXTURE=<file>` makes `snapshot`/`collect` print that file verbatim, with no provider calls and no state written.

## push.json and the FCM message

```json
{ "projectId": "your-project", "serviceAccount": "~/.config/ai-meter/fcm-service-account.json", "topic": "meters" }
```

- Auth: service-account JWT (RS256 via `openssl`, scope `https://www.googleapis.com/auth/firebase.messaging`) exchanged at the key's `token_uri`; access token cached in `<state>/fcm-token.json` (0600) until 5 min before expiry.
- Send: `POST https://fcm.googleapis.com/v1/projects/<projectId>/messages:send`

```json
{ "message": { "topic": "meters",
  "data": { "p": "<phone payload, compact JSON string>" },
  "android": { "priority": "high", "ttl": "900s", "collapse_key": "meters" } } }
```

- Phone payload = the snapshot with only `phone: true` meters, and per meter only `id,type,label,sub,ok,source,age,plan,reason,bars`. Must stay under 3500 bytes; if larger, fail with a clear error.
- Change detection ignores `ts`, `age`, `reset_at`.
- Overrides for tests: `AI_METER_FCM_URL` (send URL prefix), `AI_METER_TOKEN_URL`, `AI_METER_CURL`.
