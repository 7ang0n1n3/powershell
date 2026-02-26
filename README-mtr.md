# mtr.ps1

A lightweight MTR (Matt's Traceroute) clone written in PowerShell. Combines traceroute and continuous ping into a single live-updating terminal display, showing per-hop latency and packet-loss statistics — no external tools required.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- **Windows:** no elevation needed (WinPcap not required; uses .NET `Ping`)
- **Linux/macOS:** requires root or `cap_net_raw` capability on the `pwsh` binary

  ```bash
  # Linux — grant capability once
  sudo setcap cap_net_raw+ep $(which pwsh)

  # or simply run with sudo
  sudo pwsh ./mtr.ps1 8.8.8.8
  ```

## Usage

```powershell
.\mtr.ps1 [-Target] <host> [options]
```

### Parameters

| Parameter | Alias | Default | Description |
|-----------|-------|---------|-------------|
| `-Target` | *(positional)* | *(required)* | Hostname or IP address to trace to |
| `-MaxHops` | `-m` | `30` | Maximum TTL depth (number of hops) to probe |
| `-Count` | `-c` | `0` | Rounds to run. `0` = run indefinitely until Ctrl+C |
| `-Interval` | | `1.0` | Seconds between rounds |
| `-NoResolve` | `-n` | off | Skip reverse-DNS hostname lookups |
| `-PingTimeout` | | `1000` | Per-probe ICMP timeout in milliseconds |
| `-Report` | `-r` | off | Non-interactive mode: run `-Count` rounds then print final table. Requires `-Count > 0` |

## Examples

```powershell
# Live interactive trace (Ctrl+C to stop)
.\mtr.ps1 8.8.8.8

# Trace a hostname, limit to 20 hops, skip DNS
.\mtr.ps1 google.com -m 20 -n

# Faster updates, shorter timeout
.\mtr.ps1 192.168.1.1 -Interval 0.5 -PingTimeout 500

# Run 100 rounds then exit with a final report
.\mtr.ps1 example.com -c 100 -r

# Run 50 rounds of a limited-depth trace, no DNS
.\mtr.ps1 10.0.0.1 -c 50 -m 15 -n -r
```

## Display

The screen clears on startup and the table is pinned to the top. On the first round, each hop row appears as its ICMP reply arrives — the table grows live as the route is discovered. From round two onward the full table redraws in place once per round.

```
 MTR  ─  google.com (142.250.80.46)   2026-02-26 12:00:00   Ctrl+C to quit
 ────────────────────────────────────────────────────────────────────────────
   #  Host                               Loss%   Snt   Rcv    Last     Avg    Best   Worst   StDev
   1  _gateway (192.168.1.1)              0.0%    42    42     1.3     1.2     0.8     3.1     0.3
   2  100.64.0.1                          0.0%    42    42     5.1     5.4     4.7     8.9     0.8
   3  ???                               100.0%    42     0      --      --      --      --      --
   4  72.14.215.165                       0.0%    42    42    11.2    11.0    10.4    12.8     0.5
   5  142.250.80.46                       0.0%    42    42    12.4    12.1    11.6    14.2     0.6
 ────────────────────────────────────────────────────────────────────────────
 Round 42   Interval: 1s   Timeout: 1000ms
```

### Column Definitions

| Column | Description |
|--------|-------------|
| `#` | Hop number (TTL value) |
| `Host` | Hostname (if resolved) and IP address. `???` = no ICMP reply |
| `Loss%` | Percentage of probes that received no response |
| `Snt` | Total probes sent to this hop |
| `Rcv` | Total responses received from this hop |
| `Last` | RTT of the most recent probe (ms) |
| `Avg` | Running mean RTT (ms) |
| `Best` | Lowest RTT seen (ms) |
| `Worst` | Highest RTT seen (ms) |
| `StDev` | Running sample standard deviation of RTT (ms) |

### Colour Coding

| Colour | Loss% meaning |
|--------|---------------|
| Green | 0% — no loss |
| Yellow | > 0% and < 10% — some loss |
| Red | ≥ 10% — significant loss |

Hops with no reply (`???`) are shown in grey.

## How It Works

Each round sends one ICMP echo request per hop, with TTL set to the hop's position (1, 2, 3 …). Routers that receive a packet with TTL = 1 return an ICMP Time Exceeded message, revealing their IP. The final destination responds with ICMP Echo Reply, at which point the maximum TTL is capped to avoid probing beyond it.

Standard deviation is computed using **Welford's online algorithm** — a single-pass, numerically stable method that uses O(1) memory regardless of how many rounds have run.

DNS lookups are performed once per discovered IP and cached for the lifetime of the session. Use `-NoResolve` to skip them entirely if latency from reverse-DNS matters.

## Report Mode

With `-Report` and `-Count N`, the script runs silently for N rounds, prints a progress counter, then renders the final statistics table and exits. Useful for scripted diagnostics or logging:

```powershell
.\mtr.ps1 8.8.8.8 -c 60 -r | Tee-Object -FilePath mtr-report.txt
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Completed normally |
| `1` | Invalid arguments (e.g. `-Report` without `-Count`) or DNS resolution failure |
