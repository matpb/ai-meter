#!/usr/bin/env bash
# Test stub for codex.sh — controlled entirely by AI_METER_TEST_* env vars, see tests/collector.sh.
[ -n "${AI_METER_TEST_COUNTER:-}" ] && printf 'x\n' >> "$AI_METER_TEST_COUNTER"
if [ -n "${AI_METER_TEST_ENVFILE:-}" ]; then
  printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-}" > "$AI_METER_TEST_ENVFILE"
fi

DEFAULT_OUT='{"ok":true,"source":"live","age":0,"plan":"plus","credits":"0","five":{"pct":9,"reset_in":3600,"fresh":false},"seven":{"pct":40,"reset_in":86400,"fresh":false}}'

case "${AI_METER_TEST_MODE:-ok}" in
  timeout) sleep 999 ;;
  fail) printf '{"ok":false,"reason":"%s"}\n' "${AI_METER_TEST_REASON:-boom}" ;;
  invalid) printf 'not json at all {{{\n' ;;
  crash) exit 7 ;;
  *) printf '%s\n' "${AI_METER_TEST_OUT:-$DEFAULT_OUT}" ;;
esac
