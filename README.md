# macvlan Colocation Bug — Fix Demo (Ubuntu)

Demonstrates the recommended fix (**Option 1** from the original writeup) for the
colocated-machine failure: switch the colocated deployment from macvlan to Docker's
**host networking mode** (`network_mode: host`). Host mode shares the container's network
namespace directly with the host, so there's no virtual/macvlan boundary for host↔container
or container↔container traffic to get stuck behind — which is exactly what breaks the
handshake in the macvlan case when both services are colocated.

This project uses two Compose **profiles** so you can run the broken version and the fixed
version side-by-side with the same containers, same commands, same host — the only variable
is the network mode.

| Profile | Network mode | Expected result |
|---|---|---|
| `buggy` | macvlan | Host → container handshake **fails** (reproduces the original bug) |
| `fixed` | `network_mode: host` | Handshake **succeeds**, both host→container and container→container |

## Prerequisites (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin netcat-openbsd iproute2
sudo usermod -aG docker "$USER"   # log out/in to drop 'sudo' if you prefer
```

Find your parent interface (needed only for the `buggy` profile):
```bash
ip -o -4 addr show
```

## Setup

```bash
cp .env.example .env
nano .env   # fill in PARENT_IFACE/SUBNET/GATEWAY/SERVER_IP/CLIENT_IP for buggy profile,
            # and FIXED_PORT (any free port, e.g. 5000) for the fixed profile

chmod +x run-buggy.sh run-fixed.sh compare.sh cleanup.sh
```

## Run just the fix

```bash
./run-fixed.sh
```
Expected output: both the host→container and container→container tests succeed, since
`server-host` and `client-host` are both bound directly into the host's real network stack —
there's no macvlan network for the handshake to fail against.

## Run the full before/after comparison

```bash
./compare.sh
```
This runs the `buggy` profile first (handshake fails), tears it down, then runs the `fixed`
profile (handshake succeeds) — isolating `network_mode` as the single variable that matters.

## Cleanup

```bash
./cleanup.sh
```

## Applying this to the real V2X plugin / execution manager

The fix in the real system is the same idea, applied conditionally:

- **Cross-machine deployment:** keep the existing macvlan setup — it already works and gives
  each service a real, routable LAN IP that the other machine can dial.
- **Colocated deployment:** run the plugin and execution manager with `network_mode: host`
  (or the Docker Compose equivalent `network_mode: "host"` per service) instead of attaching
  them to the macvlan network. Both processes then bind to the host's real IP/loopback
  directly, and the handshake never has to cross the macvlan isolation boundary.

A practical way to wire this up without maintaining two separate Compose files long-term is a
deploy-time flag or environment check (e.g. "are both services scheduled on the same node?")
that selects which network mode to apply — same pattern as the `buggy`/`fixed` profiles here,
just decided automatically instead of manually.

**Trade-off to flag to the team:** host networking removes Docker's network isolation for
that container — it's now sharing the host's actual ports/interfaces, so port conflicts with
other host services become possible, and firewall/security posture should be reviewed the
same way you would for a bare-metal process, not a typical containerized one.
