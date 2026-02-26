<#
.SYNOPSIS
    Lightweight Telnet client in PowerShell.

.DESCRIPTION
    Connects to a remote host via TCP and provides an interactive terminal session.
    Handles Telnet option negotiation (RFC 854/855) and supports basic terminal I/O.

.PARAMETER Host
    The hostname or IP address to connect to.

.PARAMETER Port
    The TCP port to connect to. Defaults to 23 (standard Telnet).

.PARAMETER Timeout
    Connection timeout in milliseconds. Defaults to 5000.

.EXAMPLE
    .\telnet.ps1 -Hostname towel.blinkenlights.nl
    .\telnet.ps1 -Hostname 192.168.1.1 -Port 23
    .\telnet.ps1 -Hostname localhost -Port 8080
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Hostname,

    [Parameter(Position = 1)]
    [ValidateRange(1, 65535)]
    [int]$Port = 23,

    [int]$Timeout = 5000
)

# ── Telnet command bytes (RFC 854) ──────────────────────────────────────────
$IAC  = 255  # Interpret As Command
$DONT = 254
$DO   = 253
$WONT = 252
$WILL = 251
$SB   = 250  # Subnegotiation Begin
$SE   = 240  # Subnegotiation End

# Common options
$OPT_ECHO          = 1
$OPT_SUPPRESS_GA   = 3
$OPT_TERMINAL_TYPE = 24
$OPT_NAWS          = 31  # Negotiate About Window Size

function Send-Bytes {
    param([System.IO.Stream]$Stream, [byte[]]$Bytes)
    $Stream.Write($Bytes, 0, $Bytes.Length)
    $Stream.Flush()
}

function Handle-TelnetCommand {
    param(
        [System.IO.Stream]$Stream,
        [byte]$Cmd,
        [byte]$Opt
    )

    switch ($Cmd) {
        $DO {
            # Server asks us to DO something — agree to ECHO and SUPPRESS-GA,
            # refuse everything else.
            if ($Opt -eq $OPT_ECHO -or $Opt -eq $OPT_SUPPRESS_GA) {
                Send-Bytes $Stream ([byte[]]@($IAC, $WILL, $Opt))
            } else {
                Send-Bytes $Stream ([byte[]]@($IAC, $WONT, $Opt))
            }
        }
        $DONT {
            Send-Bytes $Stream ([byte[]]@($IAC, $WONT, $Opt))
        }
        $WILL {
            # Server wants to DO something — agree to ECHO and SUPPRESS-GA,
            # refuse terminal type / NAWS requests from server side.
            if ($Opt -eq $OPT_ECHO -or $Opt -eq $OPT_SUPPRESS_GA) {
                Send-Bytes $Stream ([byte[]]@($IAC, $DO, $Opt))
            } else {
                Send-Bytes $Stream ([byte[]]@($IAC, $DONT, $Opt))
            }
        }
        $WONT {
            Send-Bytes $Stream ([byte[]]@($IAC, $DONT, $Opt))
        }
    }
}

function Read-TelnetStream {
    param(
        [System.IO.Stream]$Stream,
        [System.Text.StringBuilder]$Buffer
    )

    while ($Stream.DataAvailable) {
        $b = $Stream.ReadByte()
        if ($b -lt 0) { return $false }   # connection closed

        if ($b -eq $IAC) {
            $cmd = $Stream.ReadByte()
            if ($cmd -lt 0) { return $false }

            if ($cmd -eq $SB) {
                # Skip subnegotiation bytes until IAC SE
                while ($true) {
                    $sb = $Stream.ReadByte()
                    if ($sb -lt 0) { return $false }
                    if ($sb -eq $IAC) {
                        $se = $Stream.ReadByte()
                        if ($se -eq $SE) { break }
                    }
                }
            } elseif ($cmd -in @($DO, $DONT, $WILL, $WONT)) {
                $opt = $Stream.ReadByte()
                if ($opt -lt 0) { return $false }
                Handle-TelnetCommand -Stream $Stream -Cmd $cmd -Opt $opt
            }
            # $cmd -eq $IAC means literal 0xFF data byte — ignore for now
        } else {
            # Skip bare Carriage Return (CR NUL / CR LF handled below)
            if ($b -eq 13) {
                $next = $Stream.ReadByte()
                if ($next -eq 0) {
                    # CR NUL → CR
                    [void]$Buffer.Append([char]13)
                } elseif ($next -eq 10) {
                    # CR LF → newline
                    [void]$Buffer.Append([char]10)
                } else {
                    [void]$Buffer.Append([char]13)
                    if ($next -gt 0) { [void]$Buffer.Append([char]$next) }
                }
            } else {
                [void]$Buffer.Append([char]$b)
            }
        }
    }
    return $true
}

# ── Main ────────────────────────────────────────────────────────────────────

Write-Host "Connecting to ${Hostname}:${Port}..." -ForegroundColor Cyan

try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $ar     = $client.BeginConnect($Hostname, $Port, $null, $null)

    if (-not $ar.AsyncWaitHandle.WaitOne($Timeout)) {
        $client.Dispose()
        Write-Error "Connection timed out after ${Timeout}ms."
        exit 1
    }
    $client.EndConnect($ar)
} catch {
    Write-Error "Failed to connect: $_"
    exit 1
}

Write-Host "Connected. Press Ctrl+] to quit.`n" -ForegroundColor Green

$stream  = $client.GetStream()
$recvBuf = [System.Text.StringBuilder]::new()

# Offer to suppress Go-Ahead from our side
Send-Bytes $stream ([byte[]]@($IAC, $WILL, $OPT_SUPPRESS_GA))

try {
    while ($client.Connected) {
        # ── Receive ────────────────────────────────────────────────────────
        if ($stream.DataAvailable) {
            $ok = Read-TelnetStream -Stream $stream -Buffer $recvBuf
            if (-not $ok) { break }

            if ($recvBuf.Length -gt 0) {
                Write-Host $recvBuf.ToString() -NoNewline
                [void]$recvBuf.Clear()
            }
        }

        # ── Send (non-blocking key check) ──────────────────────────────────
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)   # $true = do not echo

            # Ctrl+] → quit  (mimics classic telnet escape)
            if ($key.Key -eq [ConsoleKey]::RightSquareBracket -and
                $key.Modifiers -band [ConsoleModifiers]::Control) {
                Write-Host "`n`nConnection closed by user." -ForegroundColor Yellow
                break
            }

            $ch = $key.KeyChar

            # Map Enter → CR LF for Telnet
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Send-Bytes $stream ([byte[]]@(13, 10))
                continue
            }

            # Map Backspace
            if ($key.Key -eq [ConsoleKey]::Backspace) {
                Send-Bytes $stream ([byte[]]@(8))
                continue
            }

            # Send printable characters
            if ($ch -ne [char]0) {
                $encoded = [System.Text.Encoding]::ASCII.GetBytes([string]$ch)
                Send-Bytes $stream $encoded
            }
        }

        Start-Sleep -Milliseconds 10
    }
} finally {
    $stream.Dispose()
    $client.Dispose()
    Write-Host "Disconnected from ${Hostname}:${Port}." -ForegroundColor Cyan
}
