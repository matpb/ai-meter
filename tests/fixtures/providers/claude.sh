#!/usr/bin/env bash
# Test stub for claude.sh — controlled entirely by AI_METER_TEST_* env vars, see tests/collector.sh.
if [ "${1:-}" = "--list-profiles" ]; then
  printf '[]\n'
  exit 0
fi

[ -n "${AI_METER_TEST_COUNTER:-}" ] && printf 'x\n' >> "$AI_METER_TEST_COUNTER"
if [ -n "${AI_METER_TEST_ENVFILE:-}" ]; then
  printf 'CLAUDE_USAGE_DIR=%s\nCLAUDE_CHROME_COOKIES=%s\n' "${CLAUDE_USAGE_DIR:-}" "${CLAUDE_CHROME_COOKIES:-}" \
    > "$AI_METER_TEST_ENVFILE"
fi

DEFAULT_OUT='{"ok":true,"source":"token","age":0,"five":{"pct":9,"reset_in":3600},"seven":{"pct":40,"reset_in":86400},"model":{"name":"Fable","pct":12,"reset_in":86400}}'

case "${AI_METER_TEST_MODE:-ok}" in
  timeout) sleep 999 ;;
  fail) printf '{"ok":false,"reason":"%s"}\n' "${AI_METER_TEST_REASON:-boom}" ;;
  invalid) printf 'not json at all {{{\n' ;;
  crash) exit 7 ;;
  *) printf '%s\n' "${AI_METER_TEST_OUT:-$DEFAULT_OUT}" ;;
esac
