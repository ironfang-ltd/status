# Ironfang status

Public status page for [Ironfang](https://ironfang.uk) services, live at
[status.ironfang.uk](https://status.ironfang.uk).

A GitHub Actions job probes the public endpoints every five minutes from
GitHub's network - deliberately outside Ironfang's own infrastructure, so the
page stays truthful even when that infrastructure has a bad day. Results land
in `data/` and the page renders 90 days of history from them.

To post a maintenance or incident notice, put a message in `data/notice.json`:

```json
{"message": "Planned maintenance tonight 22:00-23:00 UTC."}
```

and delete it (or empty the message) when done.
