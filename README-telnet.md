# telnet.ps1

A lightweight Telnet client written in PowerShell. Connects to any TCP host and provides an interactive terminal session with full RFC 854/855 option negotiation — no external tools or Windows features required.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- No elevated privileges needed

## Usage

```powershell
.\telnet.ps1 [-Hostname] <host> [[-Port] <port>] [-Timeout <ms>]
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Hostname` | string | *(required)* | Hostname or IP address to connect to |
| `-Port` | int | `23` | TCP port number (1–65535) |
| `-Timeout` | int | `5000` | Connection timeout in milliseconds |

### Keyboard Controls

| Key | Action |
|-----|--------|
| Any printable key | Send character to server |
| Enter | Send CR LF (Telnet line ending) |
| Backspace | Send backspace byte (0x08) |
| Ctrl+] | Disconnect and exit |

## Examples

```powershell
# Connect to a classic Telnet server
.\telnet.ps1 192.168.1.1

# Specify port explicitly
.\telnet.ps1 -Hostname 192.168.1.1 -Port 23

# Connect to a raw TCP service (e.g. a game MUD)
.\telnet.ps1 mud.example.com 4000

# Shorter connection timeout
.\telnet.ps1 10.0.0.1 -Timeout 2000

# Test a local HTTP server interactively
.\telnet.ps1 localhost 8080
```

## How It Works

The script opens a raw `TcpClient` connection and runs a single-threaded I/O loop:

- **Receive path** — reads bytes from the stream, strips all IAC command sequences before printing to the terminal. Handles `CR NUL` and `CR LF` line-ending variants per the Telnet spec.
- **Send path** — polls `[Console]::KeyAvailable` without blocking, maps Enter and Backspace to the correct Telnet byte sequences, and sends all other printable characters as ASCII.

### Telnet Option Negotiation

Responds correctly to the four negotiation commands (`DO`, `DONT`, `WILL`, `WONT`):

| Option | Behaviour |
|--------|-----------|
| ECHO (1) | Accepted (WILL/DO) |
| SUPPRESS-GO-AHEAD (3) | Accepted (WILL/DO) |
| All others | Refused (WONT/DONT) |

Subnegotiation blocks (`SB … SE`) are silently consumed and discarded.

On connect, the client immediately sends `IAC WILL SUPPRESS-GO-AHEAD` to put the server into character mode.

## Limitations

- ASCII only — no UTF-8 or multi-byte character set support
- No terminal emulation (VT100/ANSI sequences pass through raw)
- No SSH; plain TCP only
