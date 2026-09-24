#!/usr/bin/env bash
# Test stub for grok.sh — controlled entirely by AI_METER_TEST_* env vars, see tests/collector.sh.
[ -n "${AI_METER_TEST_COUNTER:-}" ] && printf 'x\n' >> "$AI_METER_TEST_COUNTER"
if [ -n "${AI_METER_TEST_ENVFILE:-}" ]; then
  printf 'GROK_HOME=%s\n' "${GROK_HOME:-}" > "$AI_METER_TEST_ENVFILE"
fi

DEFAULT_OUT='{"ok":true,"source":"live","age":0,"plan":"SuperGrok","five":{"pct":5,"reset_in":86400,"fresh":false},"seven":{"pct":40,"reset_in":604800,"fresh":false}}'

case "${AI_METER_TEST_MODE:-ok}" in
  timeout) sleep 999 ;;
  fail) printf '{"ok":false,"reason":"%s"}\n' "${AI_METER_TEST_REASON:-boom}" ;;
  invalid) printf 'not json at all {{{\n' ;;
  crash) exit 7 ;;
  *) printf '%s\n' "${AI_METER_TEST_OUT:-$DEFAULT_OUT}" ;;
esac
