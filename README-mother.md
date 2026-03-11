# mother.ps1 — MU/TH/UR 6000 Network Reconnaissance Suite

A retro-themed TUI network reconnaissance tool written in pure PowerShell. Presents a green phosphor CRT interface with seven independently runnable diagnostic modules — no external binaries required for core functionality.

Inspired by the Rust/Ratatui original at [`/home/tangonine/Lab/mother`](../mother).

## Requirements

- PowerShell 5.1 (Windows) or PowerShell 7+ (cross-platform)
- No elevated privileges needed on Windows
- **Linux/macOS:** the MTR module's native ICMP fallback requires `cap_net_raw` or `sudo` (same requirement as `mtr.ps1`)

  ```bash
  sudo setcap cap_net_raw+ep $(which pwsh)
  # or run the whole tool with sudo
  sudo pwsh ./mother.ps1
  ```

## Usage

```powershell
.\mother.ps1
```

No parameters. The interface is entirely keyboard-driven.

## Interface

```
╔══════════════════════════════════════════════════════════════════╗
║     MU/TH/UR 6000  ◆  WEYLAND-YUTANI CORP  ◆  NETWORK INTEL   ║
╠════════════════════╦═════════════════════════════════════════════╣
║ MODULES            ║ OUTPUT                                      ║
║ ▶ PORT SCAN        ║                                             ║
║   PING             ║  ...module output...                        ║
║   TRACEROUTE       ║                                             ║
║   DNS LOOKUP       ║                                             ║
║   ARP SCAN         ║                                             ║
║   WHOIS            ║                                             ║
║   MTR              ║                                             ║
║ ──────────────── ═ ║                                             ║
║  ASYNC TCP         ║                                             ║
║  CONNECT SCAN      ║                                             ║
╠════════════════════╩═════════════════════════════════════════════╣
║ > target input_                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║ ◆ STATUS  ◆  SCROLL:AUTO  ◆  [↑↓/JK] SEL  [ENTER] INPUT  ...  ║
╚══════════════════════════════════════════════════════════════════╝
```

The layout adapts to the terminal size. The output panel scrolls independently of the module list.

## Keyboard Controls

### Browse mode (default)

| Key | Action |
|-----|--------|
| `↑` / `k` | Select previous module |
| `↓` / `j` | Select next module |
| `Enter` / `Tab` | Enter input mode for the selected module |
| `PgUp` / `PgDn` | Scroll output panel up / down |
| `m` | Toggle audio mute |
| `q` | Quit |

### Input mode

| Key | Action |
|-----|--------|
| Type | Append to target string |
| `Backspace` | Delete last character |
| `Enter` | Execute the selected module against the target |
| `Ctrl+U` | Clear the input field |
| `Esc` / `Tab` | Cancel, return to Browse mode |

### Running mode

| Key | Action |
|-----|--------|
| `PgUp` / `PgDn` | Scroll output panel |
| `m` | Toggle audio mute |
| `q` | Abort scan and quit |

Output auto-scrolls as lines arrive. `PgUp` disables auto-scroll; `PgDn` to the bottom re-enables it.

## Modules

### PORT SCAN

Async TCP connect scan using native .NET `TcpClient`. Fires all connections concurrently and harvests results with a shared 3-second deadline.

**Target format:** `HOST [PORT_SPEC]`

| Port spec | Example | Behaviour |
|-----------|---------|-----------|
| *(omitted)* | `192.168.1.1` | Scans ports 1–1024 |
| Range | `192.168.1.1 1-65535` | Scans the specified range |
| Single | `192.168.1.1 443` | Scans one port |
| Comma list | `192.168.1.1 22,80,443` | Scans listed ports |

Open ports are highlighted bright green. Common service names (SSH, HTTP, HTTPS, RDP, etc.) are resolved from a built-in lookup table.

---

### PING

Runs the system `ping` utility and streams output line by line.

**Target format:** `HOST [COUNT]`

```
8.8.8.8
8.8.8.8 10
google.com 5
```

Defaults to 4 packets. Uses `-c` on Linux/macOS and `-n` on Windows.

---

### TRACEROUTE

Runs `traceroute` (Linux/macOS) or `tracert` (Windows) and streams output as it arrives.

**Target format:** `HOST`

```
8.8.8.8
google.com
```

---

### DNS LOOKUP

Queries DNS resource records. Resolution chain: `Resolve-DnsName` (Windows) → `dig` → `nslookup`.

**Target format:** `DOMAIN [TYPE]`

| Example | Description |
|---------|-------------|
| `example.com` | A record (default) |
| `example.com MX` | Mail exchange records |
| `example.com AAAA` | IPv6 addresses |
| `example.com NS` | Nameservers |
| `example.com TXT` | TXT records |

---

### ARP SCAN

Discovers hosts on the local network using the ARP table. Resolution chain: `Get-NetNeighbor` (Windows) → `ip neigh show` (Linux) → `arp -a`.

**Target format:** `CIDR` or blank

```
                    ← blank scans all interfaces
192.168.1.0/24
```

Reachable/stale entries are highlighted. On Windows, `Get-NetNeighbor` may require an elevated shell to see all entries.

---

### WHOIS

Queries registration information for a domain or IP address. Falls back to a raw TCP connection to `whois.iana.org:43` with automatic referral following if the `whois` binary is not installed.

**Target format:** `DOMAIN or IP`

```
example.com
8.8.8.8
github.com
```

Comment lines (`%`, `#`) are dimmed. `key: value` pairs are highlighted.

---

### MTR

Continuous multi-hop route analysis. Resolution chain:

1. **`mtr` binary** — runs `mtr --report --report-cycles N --no-dns HOST` and streams results. Requires `cap_net_raw` or `sudo` on Linux. If the binary runs but produces no output (permission error), falls back automatically.
2. **Native ICMP** — pure .NET `Ping`-based traceroute with per-hop statistics (loss%, sent, received, last/avg/best/worst RTT). Requires `cap_net_raw` or `sudo` on Linux.

> For a live updating per-hop display with standard deviation, use `.\mtr.ps1` directly.

**Target format:** `HOST [CYCLES]`

```
8.8.8.8
8.8.8.8 20
google.com 5
```

Defaults to 10 cycles.

## Audio

Distinct tones play for: boot, module selection, input mode, keypress, scan start, scan complete, error, and cancel. All synthesised via `[Console]::Beep()`. Press `m` at any time to toggle mute.

## Architecture

| Concern | Implementation |
|---------|---------------|
| TUI rendering | ANSI escape sequences + `Console.SetCursorPosition` (same technique as `mtr.ps1`) |
| Module execution | Each scan runs in an isolated `[Runspace]` |
| Output streaming | `ConcurrentQueue[hashtable]` drained each frame (~80 ms tick) |
| Alternate screen | `\e[?1049h` / `\e[?1049l` — terminal state is fully restored on exit or panic |
| Compatibility | Single file, PS 5.1 + PS 7+, cross-platform |
