# Changelog

All notable changes to `mtr.ps1` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.0.0] — 2026-03-07

### Added
- **Redesigned header** — three-line header replaces the old single-line title:
  - Line 1: `MTR - Powershell version (v1.0)` centred to terminal width
  - Line 2: `SRC <hostname> (<ip>) -> DST <hostname> (<ip>)   <date/time>`
  - Line 3: `KEYS : [q]uit  [R]estart statistics`
- **Source IP detection** — uses a UDP socket connect to the target to determine the correct outbound LAN interface IP (never localhost); compatible with Windows PowerShell 5.1 and PowerShell 7+.
- **Interactive keys** — non-blocking key polling during both probing and inter-round sleep:
  - `q` — quit cleanly (equivalent to Ctrl+C)
  - `R` — reset all statistics and re-discover the route from scratch
- **Per-hop loss highlighting**:
  - Entire row rendered **bold** when the hop has any cumulative packet loss
  - Host and Loss% columns rendered **red + bold** when the most recent probe to that hop was lost (tracked via a `LastLost` flag on each hop)

### Changed
- `$numLines` line-count updated from 5 → 7 to account for the two new header lines, keeping cursor repositioning accurate during live redraws.
- Main loop restructured: outer `while (-not $shouldQuit)` with an inner restart gate replaces the previous `while ($true)` / `break` pattern.
- Inter-round sleep replaced with a 50 ms polling loop so key presses are handled promptly.

---

## [0.2.0] — 2026-02-26

### Added
- PS 5.1 compatibility fix: nested helper functions (`rj`, `lj`, `fRTT`, `fLoss`, `lossC`) hoisted to script scope to avoid PS 5.1 parse errors with functions defined inside other functions.

---

## [0.1.0] — 2026-02-26

### Added
- Initial release: live-updating MTR clone in pure PowerShell.
- ICMP probing via `.NET` `System.Net.NetworkInformation.Ping` — no external tools required.
- Per-hop statistics: Loss%, Sent, Received, Last RTT, Avg, Best, Worst, StdDev (Welford online algorithm).
- Reverse-DNS lookup with per-session cache; `‑NoResolve` (`-n`) to skip.
- `-Report` (`-r`) mode: silent run for N rounds, then prints final table — pipeable to `Tee-Object`.
- Colour-coded Loss% column: green / yellow / red thresholds.
- First-round live table growth: rows appear as each hop responds.
- Parameters: `-MaxHops` / `-m`, `-Count` / `-c`, `-Interval`, `-PingTimeout`, `-NoResolve` / `-n`, `-Report` / `-r`.
- Works on Windows PowerShell 5.1 and PowerShell 7+ (Linux/macOS requires `cap_net_raw` or `sudo`).
