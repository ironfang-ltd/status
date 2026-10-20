#!/usr/bin/env bash
# Synthetic check of the Ironfang MCP surface from outside, with curl only.
# Proves the things a client needs before it can even start: the resource
# metadata, the 401 challenge, the method restriction, the authorization
# server's advertised capabilities, and that what is running is what was
# merged. Exits non-zero with a one-line reason on the first failure.
#
#   MCP_URL=https://mcp.ironfang.com WARDEN_URL=https://id.ironfang.com scripts/mcp-canary.sh
#
# MCP_CANARY_CATALOGUE=required also insists on the public capability
# catalogue, on the site and on the MCP host. Left unset, a catalogue that is
# not there yet (the release or the host's route has not landed) is a note,
# and one that is there must still be right. Set it in the workflow once
# both answer.
set -u

MCP_URL="${MCP_URL:-https://mcp.ironfang.com}"
WARDEN_URL="${WARDEN_URL:-https://id.ironfang.com}"
SITE_URL="${SITE_URL:-https://ironfang.com}"
CATALOGUE="${MCP_CANARY_CATALOGUE:-optional}"
RESOURCE="$MCP_URL/mcp"
TIMEOUT=15

fail() { echo "mcp canary FAILED: $*" >&2; exit 1; }

# 1. Protected-resource metadata (RFC 9728), path-specific document.
prm=$(curl -sS --max-time $TIMEOUT "$MCP_URL/.well-known/oauth-protected-resource/mcp") || fail "resource metadata unreachable"
echo "$prm" | grep -q "\"resource\":\"$RESOURCE\"" || fail "resource metadata does not name $RESOURCE: $prm"
echo "$prm" | grep -q "\"authorization_servers\":\[\"$WARDEN_URL\"\]" || fail "resource metadata does not name $WARDEN_URL as authorization server"
echo "$prm" | grep -q '"ironfang:mcp"' || fail "resource metadata does not advertise ironfang:mcp"
echo "$prm" | grep -q 'offline_access' && fail "resource metadata must not advertise offline_access"

# 2. Unauthenticated POST /mcp: 401 with a challenge pointing at that document.
hdr=$(curl -sS --max-time $TIMEOUT -o /dev/null -D - -X POST "$RESOURCE" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}') || fail "POST /mcp unreachable"
echo "$hdr" | head -1 | grep -q ' 401' || fail "POST /mcp without a token did not answer 401: $(echo "$hdr" | head -1)"
echo "$hdr" | grep -qi "www-authenticate:.*resource_metadata=\"$MCP_URL/.well-known/oauth-protected-resource/mcp\"" \
    || fail "401 challenge does not point at the resource metadata"
echo "$hdr" | grep -qi 'x-ironfang-request-id:' || fail "no request id on the challenge"

# 3. Only POST on the modern endpoint.
code=$(curl -sS --max-time $TIMEOUT -o /dev/null -w '%{http_code}' "$RESOURCE") || fail "GET /mcp unreachable"
[ "$code" = "405" ] || fail "GET /mcp answered $code, expected 405"

# 4. What is running is a real commit.
ver=$(curl -sS --max-time $TIMEOUT "$MCP_URL/version") || fail "/version unreachable"
echo "$ver" | grep -Eq '"sha":"[0-9a-f]{40}"' || fail "/version has no sha: $ver"

# 5. The authorization server advertises what clients need.
asm=$(curl -sS --max-time $TIMEOUT "$WARDEN_URL/.well-known/oauth-authorization-server") || fail "authorization server metadata unreachable"
echo "$asm" | grep -q "\"issuer\":\"$WARDEN_URL\"" || fail "issuer mismatch"
echo "$asm" | grep -q '"S256"' || fail "S256 not advertised"
echo "$asm" | grep -q '"authorization_response_iss_parameter_supported":true' || fail "iss parameter not advertised"
echo "$asm" | grep -q '"client_id_metadata_document_supported":true' || fail "CIMD not advertised"
echo "$asm" | grep -q 'urn:ietf:params:oauth:grant-type:token-exchange' || fail "token exchange not advertised"

# 6. The capability catalogue: what the server offers, readable without a
# token and never a way to call anything. The same document on both hosts.
notes=""
for host in "$SITE_URL" "$MCP_URL"; do
    # A 404 from the site is an HTML page with a NUL in it; bash would warn.
    body=$(curl -sS --max-time $TIMEOUT -w '\n%{http_code}' "$host/.well-known/ironfang-mcp.json" | tr -d '\000'; exit "${PIPESTATUS[0]}") || fail "capability catalogue unreachable on $host"
    code=${body##*$'\n'}
    body=${body%$'\n'*}
    if [ "$code" = "404" ] && [ "$CATALOGUE" != "required" ]; then
        notes="$notes; no capability catalogue on $host yet"
        continue
    fi
    [ "$code" = "200" ] || fail "capability catalogue on $host answered $code"
    echo "$body" | grep -q '"schema": *"ironfang/mcp-capabilities/v1"' || fail "capability catalogue on $host is not the catalogue"
    echo "$body" | grep -q "\"mcp_endpoint\": *\"$RESOURCE\"" || fail "capability catalogue on $host does not name $RESOURCE"
    echo "$body" | grep -q '"anonymous_execution": *false' || fail "capability catalogue on $host does not rule out anonymous execution"
    echo "$body" | grep -q '"name": *"ironfang.connection.get"' || fail "capability catalogue on $host lists no tools"
done

echo "mcp canary ok: $(echo "$ver" | sed -n 's/.*"sha":"\([0-9a-f]\{7\}\).*/\1/p') at $RESOURCE$notes"
