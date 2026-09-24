#!/usr/bin/env bash
# Fake curl for push/listen tests. No network. Controlled via MB_CURL_* env vars:
#   MB_CURL_FAIL=1                exit nonzero (simulate any curl failure)
#   MB_CURL_TOKEN_COUNT=<file>    append a line per token-exchange call
#   MB_CURL_SEND_COUNT=<file>     append a line per FCM send call
#   MB_CURL_TOKEN_ASSERTION=<file> write the JWT assertion value from the last token call
#   MB_CURL_SEND_BODY=<file>      write the JSON body from the last FCM send call
#   MB_CURL_ACCESS_TOKEN, MB_CURL_EXPIRES_IN  override the fake token response
#   MB_CURL_ARGV_LOG=<file>       append the raw argv (one call per line) — used to prove no secrets leak
#   MB_CURL_SSE_DIR=<dir>         for SSE (Accept: text/event-stream) calls: connection N reads <dir>/N,
#                                  missing file = empty stream (connection closes with no data)
#   MB_CURL_SSE_CONNECT_COUNT=<file> append a line per SSE connection
#   MB_CURL_SSE_AUTH_LOG=<file>   append the Authorization header value from the last SSE call
#
# Everything sensitive (url, headers, data) is meant to arrive via -K - (stdin config), never argv;
# this stub logs argv verbatim so tests can assert that.

if [ -n "${MB_CURL_ARGV_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$MB_CURL_ARGV_LOG"
fi

data=""
headers=()
use_config_stdin=0

args=("$@")
i=0
n=${#args[@]}
while [ "$i" -lt "$n" ]; do
  a="${args[$i]}"
  case "$a" in
    -d|--data|--data-binary) i=$((i + 1)); data="${args[$i]}" ;;
    -H) i=$((i + 1)); headers+=("${args[$i]}") ;;
    -X) i=$((i + 1)) ;;
    -K)
      i=$((i + 1))
      [ "${args[$i]:-}" = "-" ] && use_config_stdin=1
      ;;
    *) ;;
  esac
  i=$((i + 1))
done

if [ "$use_config_stdin" -eq 1 ]; then
  cfg=$(cat)
  while IFS= read -r line; do
    key=$(printf '%s' "$line" | sed -n 's/^\([a-zA-Z-]*\)[[:space:]]*=.*/\1/p')
    val=$(printf '%s' "$line" | sed -n 's/^[a-zA-Z-]*[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p')
    val=$(printf '%s' "$val" | sed 's/\\"/"/g; s/\\\\/\\/g')
    case "$key" in
      data|data-binary)
        case "$val" in
          @*) data=$(cat "${val#@}") ;;
          *) data="$val" ;;
        esac
        ;;
      header) headers+=("$val") ;;
      *) ;;
    esac
  done <<<"$cfg"
fi

if [ -n "${MB_CURL_FAIL:-}" ]; then
  exit 1
fi

is_sse=0
for h in "${headers[@]}"; do
  case "$h" in
    Accept:*event-stream*) is_sse=1 ;;
  esac
done

if [ "$is_sse" -eq 1 ]; then
  if [ -n "${MB_CURL_SSE_CONNECT_COUNT:-}" ]; then
    printf 'x\n' >> "$MB_CURL_SSE_CONNECT_COUNT"
  fi
  conn_n=1
  [ -n "${MB_CURL_SSE_CONNECT_COUNT:-}" ] && conn_n=$(wc -l < "$MB_CURL_SSE_CONNECT_COUNT")
  if [ -n "${MB_CURL_SSE_AUTH_LOG:-}" ]; then
    for h in "${headers[@]}"; do
      case "$h" in
        Authorization:*) printf '%s\n' "$h" >> "$MB_CURL_SSE_AUTH_LOG" ;;
      esac
    done
  fi
  if [ -n "${MB_CURL_SSE_DIR:-}" ] && [ -f "$MB_CURL_SSE_DIR/$conn_n" ]; then
    cat "$MB_CURL_SSE_DIR/$conn_n"
  fi
  exit 0
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
