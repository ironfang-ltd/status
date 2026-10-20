# Ironfang status

Public status page for [Ironfang](https://ironfang.com) services, live at
[status.ironfang.com](https://status.ironfang.com).

A GitHub Actions job probes the public endpoints every five minutes from
GitHub's network - deliberately outside Ironfang's own infrastructure, so the
page stays truthful even when that infrastructure has a bad day. Results land
in `data/` and the page renders 90 days of history from them.

The MCP canary (`.github/workflows/mcp-canary.yml`, `scripts/mcp-canary.sh`)
also runs here, every 30 minutes, for the same reason: it checks from outside
that an MCP client can still connect to `mcp.ironfang.com`. It needs no
secrets.

To post a maintenance or incident notice, put a message in `data/notice.json`:

```json
{"message": "Planned maintenance tonight 22:00-23:00 UTC."}
```

and delete it (or empty the message) when done.
