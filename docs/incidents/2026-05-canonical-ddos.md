# 2026-05 Canonical DDoS — apt mirrors unreachable

**Status (as of 2026-05-09):** resolved upstream; residual / regional issues
possible while the backlog drains.

**Affected hosts:** `archive.ubuntu.com`, `security.ubuntu.com`,
`esm.ubuntu.com`, `ubuntu.com`, `launchpad.net` and the regional mirrors that
proxy them (e.g. `ch.archive.ubuntu.com`).

**Authoritative status page:** <https://status.canonical.com>

---

## How it shows up in the toolkit

`scripts/00-preflight.sh` probes every apt mirror configured under `/etc/apt`
over HTTP. If none answer, the run aborts before any change is made:

```
[ERROR] [00-preflight.sh] Cannot reach any apt mirror over HTTP
        (tried: http://ch.archive.ubuntu.com http://security.ubuntu.com
         https://esm.ubuntu.com) — apt will fail
[ERROR] [00-preflight.sh] Preflight failed with 1 error(s)
[ERROR] [main.sh] ===== FAIL  00-preflight ...
```

This is the toolkit working as designed — `01-base-config` runs `apt-get
upgrade` and `pkg_install`, both of which would fail noisily in the middle of
the run. Failing fast in preflight keeps the system in a clean state.

---

## Decide what to do

1. **Check upstream first.** Open <https://status.canonical.com> and the apt
   sources file on the host:

   ```bash
   curl -fsS -o /dev/null -w '%{http_code}\n' http://archive.ubuntu.com/ubuntu/
   curl -fsS -o /dev/null -w '%{http_code}\n' http://security.ubuntu.com/ubuntu/
   ```

   Anything other than `200`/`30x` for both means the path archive →
   security is still degraded for this host.

2. **Pick a recovery path** based on the response:

   | Symptom | Recommended fix |
   |---|---|
   | `000` / connection timed out from every mirror | Switch to a different regional mirror (see below). |
   | `403 Forbidden` from `archive.ubuntu.com` over HTTP | Switch the source from `http://` to `https://`. |
   | `503 Service Unavailable`, sporadic | Wait 10–30 minutes and re-run; the backlog is still draining. |
   | `200` on archive but `00-preflight` still fails | A non-canonical mirror in `/etc/apt/sources.list.d/*.sources` is the bad one — disable that file. |

---

## Workaround A — switch to a different mirror (Ubuntu 24.04 deb822 format)

Ubuntu 24.04 keeps the main mirror config in
`/etc/apt/sources.list.d/ubuntu.sources` (deb822 format), not in
`/etc/apt/sources.list`. Edit the `URIs:` line:

```bash
sudo cp /etc/apt/sources.list.d/ubuntu.sources \
        /etc/apt/sources.list.d/ubuntu.sources.bak

# Pick one mirror that is up. Examples that have been up during the incident:
#   https://nl.archive.ubuntu.com/ubuntu/
#   https://de.archive.ubuntu.com/ubuntu/
#   https://mirror.init7.net/ubuntu/
sudo sed -i 's|^URIs:.*archive.ubuntu.com.*|URIs: https://nl.archive.ubuntu.com/ubuntu/|' \
        /etc/apt/sources.list.d/ubuntu.sources

sudo apt-get update
```

Re-run preflight to confirm:

```bash
sudo ./main.sh --only=00-preflight
```

If preflight now passes, restart the full run:

```bash
sudo ./main.sh --resume
```

When Canonical declares the incident fully resolved, restore the backup:

```bash
sudo mv /etc/apt/sources.list.d/ubuntu.sources.bak \
        /etc/apt/sources.list.d/ubuntu.sources
sudo apt-get update
```

---

## Workaround B — http → https on the existing mirror

If the mirror is reachable but returns `403 Forbidden` over plain HTTP:

```bash
sudo sed -i 's|http://archive.ubuntu.com|https://archive.ubuntu.com|g; \
             s|http://security.ubuntu.com|https://security.ubuntu.com|g' \
        /etc/apt/sources.list.d/ubuntu.sources
sudo apt-get update
```

`ca-certificates` is installed on every supported Ubuntu 24.04 image, so no
extra setup is needed for HTTPS.

---

## Workaround C — wait

The toolkit is idempotent. Failing preflight has not changed the system, so
the safe option for non-urgent runs is to wait until
<https://status.canonical.com> reports green and re-run:

```bash
sudo ./main.sh
```

`--resume` is unnecessary because no module recorded completion.

---

## Why the toolkit cannot auto-fix this

Rewriting a host's apt sources without operator consent is exactly the
"silent surprise" the toolkit avoids elsewhere (see `02-partitions.sh` and
`03-ip-config.sh`, both of which require explicit confirmation before any
destructive change). Picking a mirror is a policy decision: regulated
environments may forbid traffic to non-approved hosts, air-gapped
environments may proxy through an internal mirror, and HTTPS may be
incompatible with a transparent caching proxy. Preflight surfaces the
problem; the operator chooses the fix.

---

## Verifying recovery after the incident

Once `https://status.canonical.com` reports the incident closed:

```bash
# 1. Mirrors answer
for h in archive.ubuntu.com security.ubuntu.com esm.ubuntu.com; do
    printf '%-25s ' "$h"
    curl -fsS -o /dev/null -w '%{http_code}\n' --max-time 5 "https://$h/"
done

# 2. apt index refreshes cleanly
sudo apt-get update

# 3. Preflight passes
sudo ./main.sh --only=00-preflight
```

If all three succeed, undo any temporary mirror swap (Workaround A) and
proceed with the normal run.
