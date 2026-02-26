<#
.SYNOPSIS
    Lightweight MTR (Matt's Traceroute) clone in PowerShell.

.DESCRIPTION
    Combines traceroute and continuous ping to display per-hop latency and
    packet-loss statistics with a live-updating terminal display.
    Uses ICMP via the .NET Ping class — no external tools required.

.PARAMETER Target
    Hostname or IP address to trace to.

.PARAMETER MaxHops
    Maximum number of hops to probe. Default: 30. Alias: -m

.PARAMETER Count
    Number of ping rounds to run. 0 = run indefinitely until Ctrl+C.
    Default: 0. Alias: -c

.PARAMETER Interval
    Seconds to wait between rounds. Default: 1.0.

.PARAMETER NoResolve
    Skip reverse-DNS hostname lookups. Alias: -n

.PARAMETER PingTimeout
    Per-probe ICMP timeout in milliseconds. Default: 1000.

.PARAMETER Report
    Non-interactive mode: run -Count rounds then print the final table
    and exit. Requires -Count > 0. Alias: -r

.EXAMPLE
    .\mtr.ps1 8.8.8.8
    .\mtr.ps1 google.com -m 20 -n
    .\mtr.ps1 example.com -c 100 -r
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Target,

    [Alias('m')]
    [int]$MaxHops = 30,

    [Alias('c')]
    [int]$Count = 0,

    [float]$Interval = 1.0,

    [Alias('n')]
    [switch]$NoResolve,

    [int]$PingTimeout = 1000,

    [Alias('r')]
    [switch]$Report
)

$ErrorActionPreference = 'Stop'

if ($Report -and $Count -le 0) {
    Write-Error '-Report requires -Count > 0'
    exit 1
}

# ── ANSI colour codes ─────────────────────────────────────────────────────────

$E      = [char]27
$R      = "${E}[0m"
$BOLD   = "${E}[1m"
$CYAN   = "${E}[36m"
$GREEN  = "${E}[32m"
$YELLOW = "${E}[33m"
$RED    = "${E}[31m"
$GRAY   = "${E}[90m"

# ── Hop data structure ────────────────────────────────────────────────────────

function New-Hop {
    param([int]$TTL)
    @{
        TTL      = $TTL
        IP       = '???'
        Hostname = '???'
        Sent     = 0
        Received = 0
        LastRTT  = [double]::NaN
        BestRTT  = [double]::MaxValue
        WorstRTT = [double]::NaN
        # Welford online variance state
        WN       = 0
        WMean    = 0.0
        WM2      = 0.0
    }
}

# ── Statistics helpers ────────────────────────────────────────────────────────

function Update-RTT {
    param([hashtable]$h, [long]$ms)
    $rtt = [double]$ms
    $h.Received++
    $h.LastRTT = $rtt
    if ($rtt -lt $h.BestRTT)                                  { $h.BestRTT  = $rtt }
    if ([double]::IsNaN($h.WorstRTT) -or $rtt -gt $h.WorstRTT) { $h.WorstRTT = $rtt }
    $h.WN++
    $d        = $rtt - $h.WMean
    $h.WMean += $d / $h.WN
    $h.WM2   += $d * ($rtt - $h.WMean)
}

function Get-Avg {
    param([hashtable]$h)
    if ($h.WN -gt 0) { $h.WMean } else { [double]::NaN }
}

function Get-StdDev {
    param([hashtable]$h)
    if ($h.WN -gt 1) { [Math]::Sqrt($h.WM2 / ($h.WN - 1)) } else { 0.0 }
}

function Get-Loss {
    param([hashtable]$h)
    if ($h.Sent -eq 0) { [double]::NaN } else { ($h.Sent - $h.Received) * 100.0 / $h.Sent }
}

# ── DNS cache ─────────────────────────────────────────────────────────────────

$dnsCache = @{}

function Resolve-IP {
    param([string]$ip)
    if ($NoResolve -or $ip -eq '???') { return $ip }
    if ($dnsCache.ContainsKey($ip))   { return $dnsCache[$ip] }
    try {
        $name = [Net.Dns]::GetHostEntry($ip).HostName
        $dnsCache[$ip] = $name
    } catch {
        $dnsCache[$ip] = $ip
    }
    return $dnsCache[$ip]
}

# ── Resolve target ────────────────────────────────────────────────────────────

try {
    $addrs     = [Net.Dns]::GetHostAddresses($Target)
    $targetIP  = ($addrs | Where-Object AddressFamily -eq 'InterNetwork' |
                  Select-Object -First 1).IPAddressToString
    if (-not $targetIP) {
        $targetIP = ($addrs | Select-Object -First 1).ToString()
    }
} catch {
    Write-Error "Cannot resolve '${Target}': $_"
    exit 1
}

$targetLabel = if ($Target -ne $targetIP) {
    "${BOLD}${Target}${R} (${targetIP})"
} else {
    "${BOLD}${targetIP}${R}"
}

# ── Probe ─────────────────────────────────────────────────────────────────────

$pinger = [Net.NetworkInformation.Ping]::new()
$pingBuf = [byte[]](, 0x00 * 32)

function Send-Probe {
    param([int]$ttl)
    $opts = [Net.NetworkInformation.PingOptions]::new($ttl, $true)
    try   { return $pinger.Send($targetIP, $PingTimeout, $pingBuf, $opts) }
    catch { return $null }
}

# ── Hop collection ────────────────────────────────────────────────────────────

$hops     = [Collections.Generic.List[hashtable]]::new()
$hopByTTL = @{}

function Get-Or-Add-Hop {
    param([int]$ttl)
    if (-not $hopByTTL.ContainsKey($ttl)) {
        $h = New-Hop $ttl
        $hopByTTL[$ttl] = $h
        # Insert in TTL order
        $idx = 0
        while ($idx -lt $hops.Count -and $hops[$idx].TTL -lt $ttl) { $idx++ }
        $hops.Insert($idx, $h)
    }
    return $hopByTTL[$ttl]
}

# ── Rendering helpers (script scope — avoids nested-function parser issues) ────

function rj {
    param([string]$s, [int]$n)
    $s.PadLeft($n)
}

function lj {
    param([string]$s, [int]$n)
    if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + [char]0x2026 }
    else { $s.PadRight($n) }
}

function fRTT {
    param([double]$v)
    if ([double]::IsNaN($v) -or $v -lt 0 -or $v -eq [double]::MaxValue) { '     --' }
    else { '{0,7:F1}' -f $v }
}

function fLoss {
    param([double]$v)
    if ([double]::IsNaN($v)) { '    -- ' }
    else { '{0,5:F1}%' -f $v }
}

function lossC {
    param([double]$p)
    if ([double]::IsNaN($p) -or $p -eq 0) { $GREEN }
    elseif ($p -lt 10) { $YELLOW }
    else { $RED }
}

# ── Rendering ─────────────────────────────────────────────────────────────────

$displayRow   = -1
$prevNumLines = 0

function Render-Table {
    param([int]$Round, [switch]$Final)

    $w     = [Math]::Max(80, [Console]::WindowWidth) - 1
    $hostW = [Math]::Max(24, [Math]::Min(48, $w - 62))
    $eol   = "${E}[0K`n"

    $buf = [Text.StringBuilder]::new()

    # Header
    $ts     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $status = if ($Final) { "${GREEN}Done${R}" } else { "${GRAY}Ctrl+C to quit${R}" }
    [void]$buf.Append(" ${BOLD}${CYAN}MTR${R}  --  ${targetLabel}   ${GRAY}${ts}${R}   ${status}${eol}")
    [void]$buf.Append("${GRAY}$('-' * $w)${R}${eol}")

    # Column header
    $ch  = " ${BOLD}"
    $ch += (rj '#'     3) + '  '
    $ch += (lj 'Host'  $hostW) + '  '
    $ch += (rj 'Loss%' 6) + '  '
    $ch += (rj 'Snt'   5) + '  '
    $ch += (rj 'Rcv'   5) + '  '
    $ch += (rj 'Last'  7) + '  '
    $ch += (rj 'Avg'   7) + '  '
    $ch += (rj 'Best'  7) + '  '
    $ch += (rj 'Worst' 7) + '  '
    $ch += (rj 'StDev' 7) + $R
    [void]$buf.Append("${ch}${eol}")

    # Hop rows
    foreach ($hop in $hops) {
        $hostStr = if ($hop.IP -eq '???') { '???' }
                   elseif ($hop.Hostname -ne $hop.IP) { "$($hop.Hostname) ($($hop.IP))" }
                   else { $hop.IP }

        $loss   = Get-Loss   $hop
        $avg    = Get-Avg    $hop
        $stddev = Get-StdDev $hop
        $best   = if ($hop.BestRTT -eq [double]::MaxValue) { [double]::NaN } else { $hop.BestRTT }

        $hClr = if ($hop.IP -eq '???') { $GRAY } else { $CYAN }
        $lClr = lossC $loss

        $row  = ' '
        $row += (rj "$($hop.TTL)"      3) + '  '
        $row += "${hClr}$(lj $hostStr $hostW)${R}  "
        $row += "${lClr}$(fLoss $loss)${R}  "
        $row += (rj "$($hop.Sent)"     5) + '  '
        $row += (rj "$($hop.Received)" 5) + '  '
        $row += (fRTT $hop.LastRTT)       + '  '
        $row += (fRTT $avg)               + '  '
        $row += (fRTT $best)              + '  '
        $row += (fRTT $hop.WorstRTT)      + '  '
        $row += (fRTT $stddev)
        [void]$buf.Append("${row}${eol}")
    }

    # Footer
    [void]$buf.Append("${GRAY}$('-' * $w)${R}${eol}")
    $roundInfo = if ($Count -gt 0) { "Round $Round / $Count" } else { "Round $Round" }
    [void]$buf.Append(" ${GRAY}${roundInfo}   Interval: ${Interval}s   Timeout: ${PingTimeout}ms${R}${eol}")

    $numLines = 5 + $hops.Count   # title + sep + colhdr + hops + sep + footer

    # Place/reposition cursor
    if (-not $Report) {
        if ($script:displayRow -lt 0) {
            $script:displayRow = [Console]::CursorTop
        } else {
            [Console]::SetCursorPosition(0, $script:displayRow)
        }
        [Console]::CursorVisible = $false
    }

    [Console]::Write($buf.ToString())

    # Erase leftover lines if hop count shrank (rare but safe)
    $extra = $script:prevNumLines - $numLines
    for ($i = 0; $i -lt $extra; $i++) { [Console]::Write("${E}[2K`n") }
    $script:prevNumLines = [Math]::Max($numLines, $script:prevNumLines)

    if (-not $Report) { [Console]::CursorVisible = $true }
}

# ── Main loop ─────────────────────────────────────────────────────────────────

$round       = 0
$maxReached  = $MaxHops

if ($Report) {
    Write-Host "MTR report — target: $targetLabel — $Count rounds`n" -ForegroundColor Cyan
} else {
    # Clear screen and pin the table to the top
    [Console]::Clear()
    $script:displayRow   = 0
    $script:prevNumLines = 0
}

try {
    while ($true) {
        $t0          = [DateTime]::UtcNow
        $isFirstRound = $round -eq 0

        for ($ttl = 1; $ttl -le $maxReached; $ttl++) {
            $hop = Get-Or-Add-Hop $ttl
            $hop.Sent++

            $reply = Send-Probe $ttl
            if ($null -eq $reply) {
                # Probe threw — show the hop as unresponsive immediately
                if (-not $Report -and $isFirstRound) { Render-Table -Round 0 }
                continue
            }

            switch ($reply.Status) {
                'TtlExpired' {
                    $ip = $reply.Address.ToString()
                    if ($hop.IP -ne $ip) {
                        $hop.IP       = $ip
                        $hop.Hostname = Resolve-IP $ip
                    }
                    Update-RTT $hop $reply.RoundtripTime
                }
                'Success' {
                    $ip = $reply.Address.ToString()
                    if ($hop.IP -ne $ip) {
                        $hop.IP       = $ip
                        $hop.Hostname = Resolve-IP $ip
                    }
                    Update-RTT $hop $reply.RoundtripTime
                    $maxReached = $ttl   # stop probing beyond the destination
                }
                # TimedOut / DestinationUnreachable / etc.: sent counted, no RTT
            }

            # On the first round, redraw after every hop so the table grows live
            if (-not $Report -and $isFirstRound) { Render-Table -Round 0 }
        }

        $round++

        if (-not $Report) {
            Render-Table -Round $round
        } elseif ($round % 10 -eq 0 -or $round -eq $Count) {
            Write-Host "`r  Round $round / $Count   " -NoNewline -ForegroundColor DarkGray
        }

        if ($Count -gt 0 -and $round -ge $Count) { break }

        # Sleep for the remainder of the interval
        $elapsed = ([DateTime]::UtcNow - $t0).TotalSeconds
        $wait    = $Interval - $elapsed
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
    }
} finally {
    [Console]::CursorVisible = $true

    if ($Report) {
        Write-Host ("`r" + ' ' * 40 + "`r")   # clear progress line
        $script:displayRow   = -1
        $script:prevNumLines = 0
        Render-Table -Round $round -Final
    } else {
        Render-Table -Round $round -Final
    }

    $pinger.Dispose()
}
