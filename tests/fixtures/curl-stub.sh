#!/usr/bin/env bash
# Fake curl for push tests. No network. Controlled via MB_CURL_* env vars:
#   MB_CURL_FAIL=1                exit nonzero (simulate any curl failure)
#   MB_CURL_TOKEN_COUNT=<file>    append a line per token-exchange call
#   MB_CURL_SEND_COUNT=<file>     append a line per FCM send call
#   MB_CURL_TOKEN_ASSERTION=<file> write the JWT assertion value from the last token call
#   MB_CURL_SEND_BODY=<file>      write the JSON body from the last FCM send call
#   MB_CURL_ACCESS_TOKEN, MB_CURL_EXPIRES_IN  override the fake token response
data=""
args=("$@")
i=0
n=${#args[@]}
while [ "$i" -lt "$n" ]; do
  a="${args[$i]}"
  case "$a" in
    -d) i=$((i + 1)); data="${args[$i]}" ;;
    -H) i=$((i + 1)) ;;
    -X) i=$((i + 1)) ;;
    *) ;;
  esac
  i=$((i + 1))
done

if [ -n "${MB_CURL_FAIL:-}" ]; then
  exit 1
fi

if printf '%s' "$data" | grep -q 'assertion='; then
  [ -n "${MB_CURL_TOKEN_COUNT:-}" ] && printf 'x\n' >> "$MB_CURL_TOKEN_COUNT"
  if [ -n "${MB_CURL_TOKEN_ASSERTION:-}" ]; then
    printf '%s' "$data" | sed -n 's/^.*assertion=//p' > "$MB_CURL_TOKEN_ASSERTION"
  fi
  printf '{"access_token":"%s","expires_in":%s}\n' "${MB_CURL_ACCESS_TOKEN:-fake-token}" "${MB_CURL_EXPIRES_IN:-3600}"
elif printf '%s' "$data" | grep -q '"message"'; then
  [ -n "${MB_CURL_SEND_COUNT:-}" ] && printf 'x\n' >> "$MB_CURL_SEND_COUNT"
  [ -n "${MB_CURL_SEND_BODY:-}" ] && printf '%s' "$data" > "$MB_CURL_SEND_BODY"
  printf '{"name":"projects/p/messages/1"}\n'
else
  printf '{}\n'
fi
