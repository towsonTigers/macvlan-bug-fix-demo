Details
# Reproducing the macvlan Host-Isolation Bug

This walks through a minimal example that reproduces the same failure class described in the
V2X plugin / execution manager issue: a macvlan-attached service is reachable from other
machines on the network, but **not reachable from its own Docker host**. We'll stand in
`nc` (netcat) listeners for the plugin and execution manager — no V2X-specific code needed,
since the bug is purely at the network layer.

## Prerequisites

- A Linux host with Docker installed (macvlan host-isolation is a Linux kernel behavior —
  this won't reproduce correctly on Docker Desktop for Mac/Windows, since those run Docker
  inside a VM).
- Root or sudo access (macvlan network creation requires it).
- Know your host's physical network interface name (e.g. `eth0`, `ens33`, `enp0s3`). Find it with:
  ```bash
  ip route | grep default
  ```
- Know your LAN subnet and gateway, and have **two free IPs** on that subnet not used by DHCP
  (ask your network admin or pick addresses outside your router's DHCP range).

For the examples below, substitute your actual values:
- Parent interface: `eth0`
- Subnet: `192.168.1.0/24`
- Gateway: `192.168.1.1`
- Free IP for container A: `192.168.1.50`
- Free IP for container B: `192.168.1.51`

## Step 1 — Create the macvlan network

```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  demo_macvlan
```

Verify it was created:
```bash
docker network inspect demo_macvlan
```

## Step 2 — Start a "server" container on the macvlan network

This stands in for the execution manager's listen endpoint.

```bash
docker run -dit --name server \
  --network demo_macvlan --ip 192.168.1.50 \
  --entrypoint sh alpine
```

Start a netcat listener inside it:
```bash
docker exec -it server sh -c "apk add --no-cache netcat-openbsd && nc -lk -p 5000"
```
Leave this running — it's now listening on `192.168.1.50:5000`, same as the execution
manager's listen endpoint in the original bug report.

## Step 3 — Confirm cross-machine access works (the "control" case)

From a **different machine** on the same LAN, try connecting:
```bash
nc -v 192.168.234.50 5000
```
Windows PowerShell:
```bash
Test-NetConnection -ComputerName 192.168.234.50 -Port 5000
```

This should connect successfully — mirroring the original report where the two-machine
setup worked fine after the macvlan workaround was applied.

## Step 4 — Reproduce the bug: try connecting from the Docker host itself

On the **same host** that's running the `server` container (not inside any container — from
the bare host shell):
```bash
nc -v 192.168.1.50 5000
```

**Expected result (the bug):** this hangs or times out. The host cannot reach its own
macvlan-attached container, even though the IP is on the same subnet and works fine from
every other machine. This is the exact symptom in the original report: works two-machine,
fails colocated.

You can confirm it's not a firewall/routing issue by checking the route table — the subnet
is present, but packets never get delivered because the macvlan driver blocks host↔child
traffic at the kernel level:
```bash
ip route get 192.168.1.50
tcpdump -i eth0 host 192.168.1.50   # run this while retrying the nc command above
```
You'll typically see nothing arrive on the physical interface at all — the kernel drops the
host-to-macvlan-child traffic before it hits the wire.

## Step 5 — Reproduce the "two containers, same host" variant

This one is closer to the actual plugin/execution-manager topology (two services, not host vs.
container). Start a second container also on `demo_macvlan`:

```bash
docker run -dit --name client \
  --network demo_macvlan --ip 192.168.1.51 \
  --entrypoint sh alpine
docker exec -it client sh -c "apk add --no-cache netcat-openbsd"
docker exec -it client nc -v 192.168.1.50 5000
```

Container-to-container over macvlan on the *same host* usually **does** work (traffic goes
out the physical NIC and the switch reflects it back — a.k.a. NIC/switch hairpin). Whether
this succeeds depends on your switch's hairpin/reflection support, which is why some
environments see it fail too. If it fails here as well, you've confirmed the second failure
mode (switch-level MAC reflection, not just host isolation).

## Step 6 — Apply and verify the fix (host shim interface)

To prove the root cause, add a macvlan shim on the host and repeat Step 4:

```bash
ip link add macvlan-shim link eth0 type macvlan mode bridge
ip addr add 192.168.1.52/24 dev macvlan-shim
ip link set macvlan-shim up
ip route add 192.168.1.0/24 dev macvlan-shim
```

Now retry from the host:
```bash
nc -v 192.168.1.50 5000
```
This should now succeed — confirming the shim interface resolves host→macvlan-child
communication, and that the original failure was indeed the macvlan isolation behavior.

## Step 7 — Cleanup

```bash
docker rm -f server client
docker network rm demo_macvlan
ip link del macvlan-shim   # if created in Step 6
```

## Mapping back to the real system

| Demo element | Real system |
|---|---|
| `server` container / `nc -lk -p 5000` | Execution manager's listen endpoint |
| `client` container or host `nc` | V2X plugin's handshake attempt |
| Step 3 (cross-machine) | Working two-machine case |
| Step 4 (host → macvlan container) | Colocated failure when a service runs on the bare host |
| Step 5 (container → container, same host) | Colocated failure when both services are containerized |
| Step 6 (shim fix) | Confirms macvlan isolation as root cause