# pwsh-nettools

A collection of lightweight network diagnostic and communication tools written entirely in PowerShell. No external binaries, no Windows optional features, no elevated privileges required (except where noted). All scripts run on PowerShell 5.1 and PowerShell 7+ across Windows, Linux, and macOS.

**Author:** [7ang0n1n3](https://github.com/7ANG0N1N3)

---

## Tools

### [telnet.ps1](README-telnet.md) — Telnet Client

An interactive Telnet client that connects to any TCP host and handles RFC 854/855 option negotiation transparently. Strips all IAC control sequences before printing, maps keyboard input to correct Telnet byte sequences, and supports the classic Ctrl+] escape to quit.

```powershell
.\telnet.ps1 192.168.1.1
.\telnet.ps1 mud.example.com 4000
```

**Version:** 1.0.1 &nbsp;|&nbsp; [Full documentation →](README-telnet.md)

---

### [curl.ps1](README-curl.md) — HTTP Client

A curl-compatible HTTP client supporting GET, POST, PUT, DELETE, PATCH, HEAD, and OPTIONS. Handles custom headers, JSON and form bodies, file upload, basic authentication, redirect following, cookie jars, TLS bypass, and gzip decompression. Response body is written to stdout so it pipes cleanly into `ConvertFrom-Json` and other cmdlets.

```powershell
.\curl.ps1 https://api.example.com/data
.\curl.ps1 -X POST https://api.example.com/users -d '{"name":"alice"}' -H 'Content-Type: application/json'
.\curl.ps1 -u admin https://example.com/secure -L -o result.html
```

**Version:** 1.0.1 &nbsp;|&nbsp; [Full documentation →](README-curl.md)

---

### [mtr.ps1](README-mtr.md) — My Traceroute

A live-updating network path analyser that combines traceroute and continuous ping. Clears the screen on startup and builds the hop table in real time as each TTL reply arrives. Tracks loss percentage, last/average/best/worst RTT, and standard deviation per hop using Welford's online algorithm. Supports a non-interactive report mode for scripted diagnostics.

```powershell
.\mtr.ps1 8.8.8.8
.\mtr.ps1 google.com -m 20 -n
.\mtr.ps1 example.com -c 60 -r
```

**Version:** 1.1.0 &nbsp;|&nbsp; [Full documentation →](README-mtr.md)

---

## Requirements

| Requirement | Detail |
|-------------|--------|
| PowerShell | 5.1 (Windows) or 7+ (cross-platform) |
| .NET | Included with PowerShell — no separate install |
| Privileges | None required on Windows. `mtr.ps1` needs `cap_net_raw` or `sudo` on Linux/macOS |

---

## Quick Start

```powershell
# Clone or download the scripts, then run directly:
.\telnet.ps1 towel.blinkenlights.nl
.\curl.ps1 https://httpbin.org/get | ConvertFrom-Json
.\mtr.ps1 1.1.1.1
```

If your execution policy blocks unsigned scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## Changelog

### telnet.ps1

#### v1.0.1 — 2026-02-26
- Fixed `-Hostname` parameter name collision: renamed from `-Host` which is a reserved PowerShell automatic variable

#### v1.0.0 — 2026-02-26
- Initial release
- RFC 854/855 Telnet option negotiation (DO/DONT/WILL/WONT)
- Subnegotiation (SB…SE) block skipping
- CR NUL and CR LF line-ending handling per spec
- Non-blocking I/O loop (receive + send in single thread)
- Ctrl+] escape to disconnect
- Configurable connection timeout

---

### curl.ps1

#### v1.0.1 — 2026-02-26
- Fixed alias conflict: removed `-I` alias from `-Head` parameter — PowerShell aliases are case-insensitive, causing a collision with `-i` (Include). Use `-Head` directly.

#### v1.0.0 — 2026-02-26
- Initial release
- HTTP methods: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS (and any custom verb)
- Custom request headers (`-H`, repeatable)
- Request body from string or file (`-d`, `@filename` syntax)
- Multipart form upload (`-F key=value`, `-F key=@file`, repeatable)
- Basic authentication with secure password prompt (`-u`)
- Redirect following up to 20 hops (`-L`)
- Response headers in stdout (`-i`) and verbose trace mode (`-v`)
- Netscape-format cookie jar read (`-b`) and write (`-c`)
- TLS certificate bypass (`-k`)
- gzip/deflate decompression (`-Compressed`)
- Content-Type auto-detection for JSON vs form data
- Response body routed to `[Console]::Write` for clean pipeline support
- Exit code 1 on HTTP 4xx/5xx

---

### mtr.ps1

#### v1.1.0 — 2026-02-26
- Screen is now cleared on startup; table is pinned to row 0
- First-round progressive display: each hop row appears immediately as its ICMP reply (or timeout) arrives rather than waiting for the full round to complete

#### v1.0.0 — 2026-02-26
- Initial release
- ICMP TTL probing via .NET `System.Net.NetworkInformation.Ping`
- Live in-place table redraw using ANSI escape sequences and `Console.SetCursorPosition`
- Per-hop statistics: Loss%, Sent, Received, Last/Avg/Best/Worst/StDev RTT
- Welford's online algorithm for numerically stable running standard deviation
- Reverse-DNS resolution with per-session cache (`-n` to disable)
- ANSI colour coding: green = 0% loss, yellow = <10%, red = ≥10%
- Non-interactive report mode (`-r`) with progress indicator
- Graceful Ctrl+C handling via `try/finally` (cursor always restored)
- IPv4 preference with IPv6 fallback on resolution

---

## License

Released for personal and professional use. Attribution appreciated.

*Written by [7ang0n1n3](https://github.com/7ANG0N1N3)*
