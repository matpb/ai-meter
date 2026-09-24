#!/usr/bin/env bash
# Test stub for cursor.sh — controlled entirely by AI_METER_TEST_* env vars, see tests/collector.sh.
[ -n "${AI_METER_TEST_COUNTER:-}" ] && printf 'x\n' >> "$AI_METER_TEST_COUNTER"

DEFAULT_OUT='{"ok":true,"source":"live","age":0,"plan":"Pro","cycle_sec":2592000,"total_pct":20,"five":{"pct":9,"reset_in":900000,"fresh":false},"seven":{"pct":40,"reset_in":900000,"fresh":false},"grok":{"pct":5,"reset_in":86400,"fresh":false,"week_sec":604800}}'

case "${AI_METER_TEST_MODE:-ok}" in
  timeout) sleep 999 ;;
  fail) printf '{"ok":false,"reason":"%s"}\n' "${AI_METER_TEST_REASON:-boom}" ;;
  invalid) printf 'not json at all {{{\n' ;;
  crash) exit 7 ;;
  *) printf '%s\n' "${AI_METER_TEST_OUT:-$DEFAULT_OUT}" ;;
esac
