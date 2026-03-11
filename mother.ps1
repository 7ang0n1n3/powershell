<#
.SYNOPSIS
    MU/TH/UR 6000 — Network Reconnaissance Suite
.DESCRIPTION
    Pure PowerShell TUI port of the Rust/Ratatui original.
    Green phosphor CRT aesthetic. 7 recon modules.
.EXAMPLE
    .\mother.ps1
#>
#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# ── ANSI ──────────────────────────────────────────────────────────────────────
$E          = [char]27
$ALT_ON     = "$E[?1049h"
$ALT_OFF    = "$E[?1049l"
$HIDE_CUR   = "$E[?25l"
$SHOW_CUR   = "$E[?25h"

# ── Color theme — green phosphor CRT ─────────────────────────────────────────
$CB  = "$E[38;2;57;255;20m$E[1m"          # bright  57,255,20 bold
$CN  = "$E[38;2;0;200;55m"                 # normal  0,200,55
$CD  = "$E[38;2;0;100;30m"                 # dim     0,100,30
$CF  = "$E[38;2;0;40;12m"                  # faint   0,40,12
$CE  = "$E[38;2;57;255;20m$E[1m$E[5m"     # error   bright+bold+blink
$BG  = "$E[48;2;0;8;2m"                    # bg      0,8,2
$RST = "$E[0m"
$SFG = "$E[38;2;0;8;2m"                    # selected fg (dark)
$SBG = "$E[48;2;57;255;20m"               # selected bg (bright)

# ── Box drawing (double lines) ────────────────────────────────────────────────
$TL=[char]0x2554; $TR=[char]0x2557; $BL=[char]0x255A; $BR=[char]0x255D
$HZ=[char]0x2550; $VT=[char]0x2551
$LT=[char]0x2560; $RT=[char]0x2563; $TT=[char]0x2566; $BT=[char]0x2569
$DIA=[char]0x25C6; $TRI=[char]0x25B6; $DOT=[char]0x25CF; $BULL=[char]0x2022

# ── Module descriptors ────────────────────────────────────────────────────────
$MODS = @(
    @{ Name='PORT SCAN';  Desc='ASYNC TCP CONNECT SCAN';    Hint="HOST [PORT_SPEC]  e.g. 192.168.1.1 1-1024" }
    @{ Name='PING';       Desc='ICMP ECHO PROBE';           Hint="HOST [COUNT]  e.g. 8.8.8.8 5" }
    @{ Name='TRACEROUTE'; Desc='NETWORK PATH ANALYSIS';     Hint="HOST  e.g. 8.8.8.8" }
    @{ Name='DNS LOOKUP'; Desc='DNS RESOURCE RECORD QUERY'; Hint="DOMAIN [TYPE]  e.g. example.com MX" }
    @{ Name='ARP SCAN';   Desc='LOCAL NETWORK DISCOVERY';   Hint="CIDR or blank  e.g. 192.168.1.0/24" }
    @{ Name='WHOIS';      Desc='DOMAIN/IP REGISTRATION';    Hint="DOMAIN OR IP  e.g. example.com" }
    @{ Name='MTR';        Desc='CONTINUOUS ROUTE ANALYSIS'; Hint="HOST [CYCLES]  e.g. 8.8.8.8 10" }
)

# ── App state ─────────────────────────────────────────────────────────────────
$script:AppMode    = 'Browse'   # Browse | Input | Running
$script:Sel        = 0
$script:InputText  = ''
$script:Out        = [Collections.Generic.List[hashtable]]::new()
$script:Scroll     = 0
$script:AutoScroll = $true
$script:Tick       = 0
$script:StatusMsg  = 'AWAITING INSTRUCTION.'
$script:ViewH      = 20
$script:DispRow    = 0
$script:PrevW      = 0
$script:PrevH      = 0
$script:Queue      = $null
$script:RunPS      = $null
$script:RunRS      = $null
$script:Muted      = $false

# ── Output helpers ────────────────────────────────────────────────────────────
function script:OAdd([string]$t, [string]$s) {
    $script:Out.Add(@{ Type=$t; Text=$s })
    if ($script:AutoScroll) {
        $script:Scroll = [Math]::Max(0, $script:Out.Count - $script:ViewH)
    }
}

function script:OInit {
    $script:Out.Clear()
    OAdd 'Dim'    ([string]::new([char]0x2501, 50))
    OAdd 'Bright' 'SYSTEM INITIALIZATION COMPLETE.'
    OAdd 'Normal' 'MU/TH/UR 6000 ONLINE.'
    OAdd 'Normal' 'WEYLAND-YUTANI CORP — NETWORK RECONNAISSANCE SUITE.'
    OAdd 'Bright' '7 MODULES LOADED. ALL SYSTEMS NOMINAL.'
    OAdd 'Dim'    ([string]::new([char]0x2501, 50))
    OAdd 'Normal' 'SELECT MODULE AND ENTER TARGET TO BEGIN.'
    OAdd 'Bright' 'AWAITING INSTRUCTION.'
}

# ── Sound ─────────────────────────────────────────────────────────────────────
function script:Snd([int[]]$freqs, [int[]]$durs) {
    if ($script:Muted) { return }
    try { for ($i=0;$i -lt $freqs.Count;$i++) { [Console]::Beep($freqs[$i],$durs[$i]) } } catch {}
}
function script:SndBoot   { Snd 440,660,880   60,60,100 }
function script:SndSel    { Snd @(700)  @(25) }
function script:SndKey    { Snd @(900)  @(12) }
function script:SndErr    { Snd @(180)  @(200) }
function script:SndDone   { Snd 880,1100  60,100 }
function script:SndStart  { Snd 550,770   40,60 }
function script:SndCancel { Snd @(280)  @(80) }
function script:SndInput  { Snd @(600)  @(35) }

# ── Render helpers ────────────────────────────────────────────────────────────
function script:Fit([string]$s, [int]$n) {
    if ($s.Length -gt $n) { $s.Substring(0, [Math]::Max(0,$n-1)) + [char]0x2026 }
    else { $s.PadRight($n) }
}

function script:WrapText([string]$text, [int]$w) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($word in ($text -split '\s+')) {
        if (-not $lines.Count) { $lines.Add($word); continue }
        $last = $lines[$lines.Count-1]
        if (($last + ' ' + $word).Length -le $w) { $lines[$lines.Count-1] = "$last $word" }
        else { $lines.Add($word) }
    }
    ,$lines
}

# ── Rendering ─────────────────────────────────────────────────────────────────
function script:Render {
    $W     = [Math]::Max(80, [Console]::WindowWidth) - 33
    $H     = [Console]::WindowHeight

    # On resize: clear and reanchor so borders don't bow
    if ($W -ne $script:PrevW -or $H -ne $script:PrevH) {
        [Console]::Clear()
        $script:DispRow = 0
        $script:PrevW   = $W
        $script:PrevH   = $H
    }
    # Layout: 8 fixed rows + mainH rows
    # Row 0:        top border
    # Row 1:        header content
    # Row 2:        header-bottom / main-top (col divider)
    # Row 3..2+mH:  main area
    # Row 3+mH:     main-bottom / input-top (col divider ends)
    # Row 4+mH:     input content
    # Row 5+mH:     input-bottom / status
    # Row 6+mH:     status content
    # Row 7+mH:     bottom border
    $mainH = [Math]::Max(1, $H - 16)
    $script:ViewH = $mainH

    $modI = 20                      # module column inner width
    $outI = $W - $modI - 3          # output column inner width: W = 1+modI+1+outI+1
    if ($outI -lt 10) { $outI = 10 }

    $isRun     = $script:AppMode -eq 'Running'
    $isInput   = $script:AppMode -eq 'Input'
    $outBorder = if ($isRun)   { "${CB}${BG}" } else { "${CD}${BG}" }
    $inBorder  = if ($isInput) { "${CB}${BG}" } else { "${CD}${BG}" }

    $buf = [Text.StringBuilder]::new(($W + 60) * ($H + 4))

    # helpers local to render
    $D  = "${CD}${BG}"; $B = "${CB}${BG}"; $N = "${CN}${BG}"; $F = "${CF}${BG}"
    $hz = [string]::new($HZ, 1)

    # ── Row 0: top border ────────────────────────────────────────────────────
    [void]$buf.Append("${D}${TL}$([string]::new($HZ,$W-2))${TR}${RST}`n")

    # ── Row 1: header ────────────────────────────────────────────────────────
    $date    = Get-Date -Format 'yyyy.MM.dd'
    $htitle  = " MU/TH/UR 6000  $DIA  WEYLAND-YUTANI CORP  $DIA  NETWORK INTEL  $DIA  $date "
    $innerW  = $W - 2
    $hpad    = [Math]::Max(0, [int](($innerW - $htitle.Length) / 2))
    $hline   = (Fit (' ' * $hpad + $htitle) $innerW)
    [void]$buf.Append("${D}${VT}${B}${hline}${D}${VT}${RST}`n")

    # ── Row 2: header/main separator with column divider ─────────────────────
    [void]$buf.Append("${D}${LT}$([string]::new($HZ,$modI))${TT}$([string]::new($HZ,$outI))${RT}${RST}`n")

    # ── Rows 3..2+mainH: main area ───────────────────────────────────────────
    $descLines = WrapText $MODS[$script:Sel].Desc $modI
    $outTitle  = if ($isRun) { " OUTPUT  $DOT RUNNING " } else { " OUTPUT " }

    for ($r = 0; $r -lt $mainH; $r++) {
        # module column cell
        $modCell = if ($r -lt $MODS.Count) {
            $prefix = if ($r -eq $script:Sel) { "$TRI " } else { '  ' }
            $raw    = Fit ($prefix + $MODS[$r].Name) $modI
            if ($r -eq $script:Sel) { "${SFG}${SBG}${raw}${RST}${D}" }
            else                    { "${N}${raw}${RST}${D}" }
        } elseif ($r -eq $MODS.Count) {
            $F + [string]::new([char]0x2500, $modI) + "${RST}${D}"
        } else {
            $di = $r - $MODS.Count - 1
            if ($di -lt $descLines.Count) { $F + (Fit $descLines[$di] $modI) + "${RST}${D}" }
            else                          { ' ' * $modI }
        }

        # output column cell
        $idx     = $script:Scroll + $r
        $outCell = if ($idx -lt $script:Out.Count) {
            $item  = $script:Out[$idx]
            $raw   = Fit (' ' + $item.Text) $outI
            $color = switch ($item.Type) {
                'Bright' { $B }; 'Dim' { $D }; 'Error' { "${CE}${BG}" }; default { $N }
            }
            "${color}${raw}${RST}"
        } else { ' ' * $outI }

        [void]$buf.Append("${D}${VT}${RST}${modCell}${outBorder}${VT}${RST}${outCell}${outBorder}${VT}${RST}`n")
    }

    # ── main/input separator — embed module name as input title ──────────────
    $modName  = $MODS[$script:Sel].Name
    $ititle   = " TARGET $DIA $modName "
    $fillLen  = [Math]::Max(0, $outI - $ititle.Length)
    $iSepR    = [string]::new($HZ, $fillLen) + $ititle
    [void]$buf.Append("${D}${LT}$([string]::new($HZ,$modI))${BT}${RST}${inBorder}${iSepR}${RT}${RST}`n")

    # ── input content ─────────────────────────────────────────────────────────
    $cursor  = if ($script:Tick % 10 -lt 5) { [char]0x2588 } else { ' ' }
    $iPrompt = ' >> '
    $iRaw    = if ($isInput) {
        Fit ($iPrompt + $script:InputText + $cursor) ($W - 2)
    } elseif ($script:InputText) {
        Fit ($iPrompt + $script:InputText) ($W - 2)
    } else {
        Fit ($iPrompt + $MODS[$script:Sel].Hint) ($W - 2)
    }
    $iStyle  = if ($isInput) { $B } elseif ($script:InputText) { $N } else { $F }
    [void]$buf.Append("${inBorder}${VT}${RST}${iStyle}${iRaw}${RST}${inBorder}${VT}${RST}`n")

    # ── input/status separator ────────────────────────────────────────────────
    [void]$buf.Append("${D}${LT}$([string]::new($HZ,$W-2))${RT}${RST}`n")

    # ── status ────────────────────────────────────────────────────────────────
    $scr   = if ($script:AutoScroll) { 'AUTO' } else { 'MANUAL' }
    $mute  = if ($script:Muted) { ' [MUTED]' } else { '' }
    $hint  = switch ($script:AppMode) {
        'Browse'  { "[$([char]0x2191)$([char]0x2193)/JK] SEL  [ENTER] INPUT  [PGUP/DN] SCROLL  [M] MUTE  [Q] QUIT" }
        'Input'   { '[ENTER] EXECUTE  [ESC/TAB] CANCEL  [CTRL+U] CLEAR' }
        'Running' { '[PGUP/DN] SCROLL  [M] MUTE  [Q] QUIT' }
    }
    $sline = Fit " $DIA $($script:StatusMsg)$mute  $DIA  SCR:$scr  $DIA  $hint " ($W - 2)
    [void]$buf.Append("${D}${VT}${RST}${D}${sline}${RST}${D}${VT}${RST}`n")

    # ── bottom border ─────────────────────────────────────────────────────────
    [void]$buf.Append("${D}${BL}$([string]::new($HZ,$W-2))${BR}${RST}`n")

    # ── write ─────────────────────────────────────────────────────────────────
    [Console]::SetCursorPosition(0, $script:DispRow)
    [Console]::CursorVisible = $false
    [Console]::Write($buf.ToString())
}

# ── Module scripts (run in runspaces; $Queue and $Target injected) ────────────
$script:ModScripts = @(

# [0] PORT SCAN ----------------------------------------------------------------
@'
function Enq([string]$t,[string]$s){$null=$Queue.TryAdd(@{Type=$t;Text=$s})}
function EnqTry([string]$t,[string]$s){$Queue.Enqueue(@{Type=$t;Text=$s})}
function QQ([string]$t,[string]$s){$Queue.Enqueue(@{Type=$t;Text=$s})}
$Q={param($t,$s);$Queue.Enqueue(@{Type=$t;Text=$s})}
$target=$Target.Trim()
if(-not $target){$Queue.Enqueue(@{Type='Error';Text='NO TARGET SPECIFIED.'});$Queue.Enqueue(@{Type='Done';Text=''});return}
$parts=$target -split '\s+',2
$dest=$parts[0]; $portSpec=if($parts.Count-gt 1){$parts[1]}else{''}   # $dest avoids $Host clash
$ports=@()
if(-not $portSpec){$ports=1..1024}
elseif($portSpec -match '^(\d+)-(\d+)$'){$ports=[int]$Matches[1]..[int]$Matches[2]}
else{
    try{$ports=$portSpec -split ',' |ForEach-Object{[int]$_.Trim()}}
    catch{$Queue.Enqueue(@{Type='Error';Text="INVALID PORT SPEC: $portSpec"});$Queue.Enqueue(@{Type='Done';Text=''});return}
}
$Queue.Enqueue(@{Type='Bright';Text="PORT SCAN: $($dest.ToUpper())  [$($ports.Count) PORTS]"})
$Queue.Enqueue(@{Type='Dim';Text='  PORT    STATE    SERVICE'})
try{
    $addrs=[Net.Dns]::GetHostAddresses($dest)
    $ip=($addrs|Where-Object{$_.AddressFamily-eq'InterNetwork'}|Select-Object -First 1)
    $ip=if($ip){$ip.IPAddressToString}else{($addrs|Select-Object -First 1).IPAddressToString}
}catch{$Queue.Enqueue(@{Type='Error';Text="DNS FAILED: $($_.Exception.Message.ToUpper())"});$Queue.Enqueue(@{Type='Done';Text=''});return}
$svc=@{20='FTP-DATA';21='FTP';22='SSH';23='TELNET';25='SMTP';53='DNS';67='DHCP';80='HTTP';110='POP3';111='RPCBIND';143='IMAP';389='LDAP';443='HTTPS';445='SMB';465='SMTPS';587='SUBMISSION';631='IPP';993='IMAPS';995='POP3S';1433='MSSQL';1521='ORACLE';2049='NFS';2375='DOCKER';3000='DEV-SERVER';3306='MYSQL';3389='RDP';4444='METASPLOIT';5000='FLASK';5432='POSTGRESQL';5900='VNC';6379='REDIS';6443='K8S-API';8080='HTTP-ALT';8443='HTTPS-ALT';8888='JUPYTER';9200='ELASTICSEARCH';9300='ES-CLUSTER';27017='MONGODB'}
$tasks=[Collections.Generic.List[object]]::new()
foreach($p in $ports){
    $c=[Net.Sockets.TcpClient]::new()
    $t=$c.ConnectAsync($ip,$p)
    $tasks.Add([pscustomobject]@{Port=$p;Client=$c;Task=$t})
}
$deadline=[DateTime]::UtcNow.AddSeconds(3)
$open=0
foreach($t in $tasks){
    $ms=[Math]::Max(0,($deadline-[DateTime]::UtcNow).TotalMilliseconds)
    $done=if($ms-gt 0){$t.Task.Wait([int]$ms)}else{$t.Task.IsCompleted}
    if($done -and $t.Task.Status-eq'RanToCompletion'){
        $sv=if($svc.ContainsKey($t.Port)){$svc[$t.Port]}else{''}
        $sv=if($sv){"  $sv"}else{''}
        $Queue.Enqueue(@{Type='Bright';Text="  $("{0,5}"-f$t.Port)/TCP  OPEN$sv"})
        $open++
    }
    try{$t.Client.Close()}catch{}
}
$Queue.Enqueue(@{Type='Dim';Text="SCAN COMPLETE. $open OPEN PORT(S) DETECTED."})
$Queue.Enqueue(@{Type='Done';Text=''})
'@

# [1] PING --------------------------------------------------------------------
@'
function RunCmd([string]$exe,[string]$argStr,[string]$okType='Normal'){
    $pi=[Diagnostics.ProcessStartInfo]::new()
    $pi.FileName=$exe; $pi.Arguments=$argStr
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    try{
        $p.Start()|Out-Null
        while(-not $p.StandardOutput.EndOfStream){
            $l=$p.StandardOutput.ReadLine()
            if($l.Trim()){$Queue.Enqueue(@{Type=$okType;Text="  $($l.ToUpper())"})}
        }
        $p.WaitForExit()
    }catch{$Queue.Enqueue(@{Type='Error';Text="SPAWN FAILED: $($_.Exception.Message.ToUpper())"})}
}
$target=$Target.Trim()
if(-not $target){$Queue.Enqueue(@{Type='Error';Text='NO TARGET SPECIFIED.'});$Queue.Enqueue(@{Type='Done';Text=''});return}
$parts=$target -split '\s+',2
$dest=$parts[0]
$count=if($parts.Count-gt 1 -and $parts[1] -match '^\d+$'){$parts[1]}else{'4'}
$Queue.Enqueue(@{Type='Bright';Text="ICMP PROBE: $($dest.ToUpper())  [$count PACKETS]"})
$isWin=if($null -ne $IsWindows){$IsWindows}else{$true}
$argStr=if($isWin){"-n $count $dest"}else{"-c $count $dest"}
RunCmd 'ping' $argStr
$Queue.Enqueue(@{Type='Dim';Text='PROBE COMPLETE.'})
$Queue.Enqueue(@{Type='Done';Text=''})
'@

# [2] TRACEROUTE --------------------------------------------------------------
@'
function RunCmd([string]$exe,[string]$argStr,[string]$okType='Normal'){
    $pi=[Diagnostics.ProcessStartInfo]::new()
    $pi.FileName=$exe; $pi.Arguments=$argStr
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    try{
        $p.Start()|Out-Null
        while(-not $p.StandardOutput.EndOfStream){
            $l=$p.StandardOutput.ReadLine()
            if($l.Trim()){$Queue.Enqueue(@{Type=$okType;Text="  $($l.ToUpper())"})}
        }
        $p.WaitForExit()
    }catch{$Queue.Enqueue(@{Type='Error';Text="SPAWN FAILED: $($_.Exception.Message.ToUpper())"})}
}
$target=$Target.Trim()
if(-not $target){$Queue.Enqueue(@{Type='Error';Text='NO TARGET SPECIFIED.'});$Queue.Enqueue(@{Type='Done';Text=''});return}
$Queue.Enqueue(@{Type='Bright';Text="NETWORK PATH ANALYSIS: $($target.ToUpper())"})
$isWin=if($null -ne $IsWindows){$IsWindows}else{$true}
$cmd=if($isWin){'tracert'}else{'traceroute'}
RunCmd $cmd $target
$Queue.Enqueue(@{Type='Dim';Text='PATH ANALYSIS COMPLETE.'})
$Queue.Enqueue(@{Type='Done';Text=''})
'@

# [3] DNS LOOKUP --------------------------------------------------------------
@'
$target=$Target.Trim()
if(-not $target){$Queue.Enqueue(@{Type='Error';Text='NO TARGET SPECIFIED.'});$Queue.Enqueue(@{Type='Done';Text=''});return}
$parts=$target -split '\s+',2
$domain=$parts[0]
$qtype=if($parts.Count-gt 1){$parts[1].ToUpper()}else{'A'}
$Queue.Enqueue(@{Type='Bright';Text="DNS QUERY: $($domain.ToUpper())  [TYPE $qtype]"})
$done=$false
# Try Resolve-DnsName (Windows/PS5.1+)
try{
    $recs=Resolve-DnsName -Name $domain -Type $qtype -ErrorAction Stop
    foreach($r in $recs){
        $line=($r|Out-String).Trim() -replace '\s+',' '
        $Queue.Enqueue(@{Type='Normal';Text="  $($line.ToUpper())"})
    }
    $done=$true
}catch{}
# Try dig
if(-not $done){
    $digCmd=Get-Command dig -ErrorAction SilentlyContinue
    if($digCmd){
        $pi=[Diagnostics.ProcessStartInfo]::new()
        $pi.FileName='dig'; $pi.Arguments="$domain $qtype +noall +answer +authority +comments"
        $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
        $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
        try{
            $p.Start()|Out-Null
            while(-not $p.StandardOutput.EndOfStream){
                $l=$p.StandardOutput.ReadLine()
                if($l.Trim()){
                    $up=$l.ToUpper()
                    $t=if($up.StartsWith(';')){@{Type='Dim';Text="  $up"}}else{@{Type='Normal';Text="  $up"}}
                    $Queue.Enqueue($t)
                }
            }
            $p.WaitForExit(); $done=$true
        }catch{}
    }
}
# Fallback: nslookup
if(-not $done){
    $pi=[Diagnostics.ProcessStartInfo]::new()
    $pi.FileName='nslookup'; $pi.Arguments="-type=$qtype $domain"
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    try{
        $p.Start()|Out-Null
        while(-not $p.StandardOutput.EndOfStream){
            $l=$p.StandardOutput.ReadLine()
            if($l.Trim()){$Queue.Enqueue(@{Type='Normal';Text="  $($l.ToUpper())"})}
        }
        $p.WaitForExit()
    }catch{$Queue.Enqueue(@{Type='Error';Text="DNS LOOKUP FAILED: $($_.Exception.Message.ToUpper())"})}
}
$Queue.Enqueue(@{Type='Dim';Text='QUERY COMPLETE.'})
$Queue.Enqueue(@{Type='Done';Text=''})
'@

# [4] ARP SCAN ----------------------------------------------------------------
@'
function StreamCmd([string]$exe,[string]$argStr,[string]$matchBright=''){
    $pi=[Diagnostics.ProcessStartInfo]::new()
    $pi.FileName=$exe; $pi.Arguments=$argStr
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    try{
        $p.Start()|Out-Null
        while(-not $p.StandardOutput.EndOfStream){
            $l=$p.StandardOutput.ReadLine()
            if($l.Trim()){
                $up=$l.ToUpper()
                $t=if($matchBright -and $up -match $matchBright){@{Type='Bright';Text="  $up"}}else{@{Type='Normal';Text="  $up"}}
                $Queue.Enqueue($t)
            }
        }
        $p.WaitForExit()
        return $true
    }catch{return $false}
}
$target=$Target.Trim()
$label=if($target){$target.ToUpper()}else{'LOCAL NETWORK'}
$Queue.Enqueue(@{Type='Bright';Text="ARP SCAN: $label"})
$done=$false
# Windows: Get-NetNeighbor
try{
    $nb=Get-NetNeighbor -ErrorAction Stop |Where-Object{$_.State -ne 'Unreachable' -and $_.State -ne 'Incomplete'}
    if($target){$prefix=($target -replace '/\d+$','') -replace '\.\d+$',''; $nb=$nb|Where-Object{$_.IPAddress -like "$prefix*"}}
    foreach($n in $nb){$Queue.Enqueue(@{Type='Bright';Text="  $($n.IPAddress.PadRight(16)) $($n.LinkLayerAddress.PadRight(20)) $($n.State) $($n.InterfaceAlias)"})}
    $done=$true
}catch{}
# Linux: ip neigh
if(-not $done -and (Get-Command ip -ErrorAction SilentlyContinue)){
    $Queue.Enqueue(@{Type='Dim';Text='  IP NEIGH:'})
    $done=StreamCmd 'ip' 'neigh show' 'REACHABLE|STALE'
}
# Fallback: arp -a
if(-not $done){
    $Queue.Enqueue(@{Type='Dim';Text='  ARP TABLE:'})
    StreamCmd 'arp' '-a' '' |Out-Null
}
$Queue.Enqueue(@{Type='Dim';Text='DISCOVERY COMPLETE.'})
$Queue.Enqueue(@{Type='Done';Text=''})
'@

# [5] WHOIS -------------------------------------------------------------------
@'
function EmitWhoisLines([string]$resp){
    foreach($l in ($resp -split "`n")){
        $l=$l.Trim(); if(-not $l){continue}
        $up=$l.ToUpper()
        if($l.StartsWith('%') -or $l.StartsWith('#')){$Queue.Enqueue(@{Type='Dim';Text="  $up"})}
        elseif($l.Contains(':')){$Queue.Enqueue(@{Type='Normal';Text="  $up"})}
        else{$Queue.Enqueue(@{Type='Dim';Text="  $up"})}
    }
}
function WhoisTcp([string]$server,[string]$query){
    $c=[Net.Sockets.TcpClient]::new(); $c.Connect($server,43)
    $s=$c.GetStream()
    $b=[Text.Encoding]::ASCII.GetBytes("$query`r`n"); $s.Write($b,0,$b.Length)
    $r=[IO.StreamReader]::new($s,[Text.Encoding]::ASCII)
    $resp=$r.ReadToEnd(); $c.Close(); return $resp
}
$target=$Target.Trim()
if(-not $target){$Queue.Enqueue(@{Type='Error';Text='NO TARGET SPECIFIED.'});$Queue.Enqueue(@{Type='Done';Text=''});return}
$Queue.Enqueue(@{Type='Bright';Text="REGISTRATION QUERY: $($target.ToUpper())"})
$done=$false
if(Get-Command whois -ErrorAction SilentlyContinue){
    $pi=[Diagnostics.ProcessStartInfo]::new()
    $pi.FileName='whois'; $pi.Arguments=$target
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    try{
        $p.Start()|Out-Null
        while(-not $p.StandardOutput.EndOfStream){
            $l=$p.StandardOutput.ReadLine(); $l=$l.Trim(); if(-not $l){continue}
            $up=$l.ToUpper()
            if($l.StartsWith('%') -or $l.StartsWith('#')){$Queue.Enqueue(@{Type='Dim';Text="  $up"})}
            elseif($l.Contains(':')){$Queue.Enqueue(@{Type='Normal';Text="  $up"})}
            else{$Queue.Enqueue(@{Type='Dim';Text="  $up"})}
        }
        $p.WaitForExit(); $done=$true
    }catch{}
}
if(-not $done){
    $Queue.Enqueue(@{Type='Dim';Text='WHOIS BINARY NOT FOUND — QUERYING WHOIS.IANA.ORG DIRECTLY.'})
    try{
        $resp=WhoisTcp 'whois.iana.org' $target
        $refer=$resp -split "`n" |Where-Object{$_ -match '^refer:\s*(\S+)'} |Select-Object -First 1
        if($refer -match '^refer:\s*(\S+)'){
            $ref=$Matches[1].Trim()
            $Queue.Enqueue(@{Type='Dim';Text="REFERRAL: $($ref.ToUpper())"})
            try{$resp=WhoisTcp $ref $target}catch{}
        }
        EmitWhoisLines $resp
    }catch{$Queue.Enqueue(@{Type='Error';Text="WHOIS FAILED: $($_.Exception.Message.ToUpper())"})}
}
$Queue.Enqueue(@{Type='Dim';Text='QUERY COMPLETE.'})
$Queue.Enqueue(@{Type='Done';Text=''})
'@

# [6] MTR ---------------------------------------------------------------------
@'
function NativeICMP([string]$dest,[int]$cyc){
    try{
        $addrs=[Net.Dns]::GetHostAddresses($dest)
        $ip=($addrs|Where-Object{$_.AddressFamily-eq'InterNetwork'}|Select-Object -First 1)
        $ip=if($ip){$ip.IPAddressToString}else{($addrs|Select-Object -First 1).IPAddressToString}
    }catch{$Queue.Enqueue(@{Type='Error';Text="DNS FAILED: $($_.Exception.Message.ToUpper())"});return}
    $maxH=30; $hops=@{}
    $pinger=[Net.NetworkInformation.Ping]::new()
    $pingBuf=[byte[]](,0x00*32)
    for($c=0;$c -lt $cyc;$c++){
        $maxTTL=$maxH
        for($ttl=1;$ttl -le $maxTTL;$ttl++){
            $opts=[Net.NetworkInformation.PingOptions]::new($ttl,$true)
            try{$r=$pinger.Send($ip,1000,$pingBuf,$opts)}catch{$r=$null}
            if(-not $hops.ContainsKey($ttl)){
                $hops[$ttl]=@{IP='???';Snt=0;Rcv=0;Last=0.0;Best=[double]::MaxValue;Worst=0.0;WN=0;WMean=0.0;WM2=0.0}
            }
            $h=$hops[$ttl]; $h.Snt++
            if($r -and ($r.Status-eq'TtlExpired'-or$r.Status-eq'Success')){
                $h.Rcv++; $h.IP=$r.Address.ToString(); $h.Last=$r.RoundtripTime
                if($r.RoundtripTime-lt$h.Best){$h.Best=$r.RoundtripTime}
                if($r.RoundtripTime-gt$h.Worst){$h.Worst=$r.RoundtripTime}
                $h.WN++; $d=$r.RoundtripTime-$h.WMean; $h.WMean+=$d/$h.WN; $h.WM2+=$d*($r.RoundtripTime-$h.WMean)
                if($r.Status-eq'Success'){$maxTTL=$ttl}
            }
        }
    }
    $pinger.Dispose()
    $hdr='  {0,-3}  {1,-16}  {2,6}  {3,5}  {4,5}  {5,7}  {6,7}  {7,7}  {8,7}' -f '#','HOST','LOSS%','SNT','RCV','LAST','AVG','BEST','WORST'
    $Queue.Enqueue(@{Type='Dim';Text=$hdr})
    foreach($ttl in ($hops.Keys|Sort-Object)){
        $h=$hops[$ttl]
        $loss=if($h.Snt-gt 0){($h.Snt-$h.Rcv)*100.0/$h.Snt}else{0}
        $avg=if($h.WN-gt 0){$h.WMean}else{0}
        $best=if($h.Best-eq[double]::MaxValue){0.0}else{$h.Best}
        $row='  {0,-3}  {1,-16}  {2,5:F1}%  {3,5}  {4,5}  {5,7:F1}  {6,7:F1}  {7,7:F1}  {8,7:F1}' -f $ttl,$h.IP,$loss,$h.Snt,$h.Rcv,$h.Last,$avg,$best,$h.Worst
        $Queue.Enqueue(@{Type='Normal';Text=$row})
    }
}
$target=$Target.Trim()
if(-not $target){$Queue.Enqueue(@{Type='Error';Text='NO TARGET SPECIFIED.'});$Queue.Enqueue(@{Type='Done';Text=''});return}
$parts=$target -split '\s+',2
$dest=$parts[0]   # avoid $host — shadows $Host automatic variable
$cycles=if($parts.Count-gt 1 -and $parts[1] -match '^\d+$'){$parts[1]}else{'10'}
$Queue.Enqueue(@{Type='Bright';Text="CONTINUOUS ROUTE ANALYSIS: $($dest.ToUpper())  [$cycles CYCLES]"})
$usedNative=$false
$mtrCmd=Get-Command mtr -ErrorAction SilentlyContinue
if($mtrCmd){
    $Queue.Enqueue(@{Type='Dim';Text='  RUNNING — THIS MAY TAKE SEVERAL SECONDS...'})
    $pi=[Diagnostics.ProcessStartInfo]::new()
    $pi.FileName='mtr'; $pi.Arguments="--report --report-cycles $cycles --no-dns $dest"
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    $hopLines=0
    try{
        $p.Start()|Out-Null
        $first=$true
        while(-not $p.StandardOutput.EndOfStream){
            $l=$p.StandardOutput.ReadLine()
            if($l.Trim()){
                $up=$l.ToUpper()
                $t=if($first){$first=$false;@{Type='Dim';Text="  $up"}}
                   elseif($up -match 'HOST|LOSS'){@{Type='Dim';Text="  $up"}}
                   else{$hopLines++;@{Type='Normal';Text="  $up"}}
                $Queue.Enqueue($t)
            }
        }
        $p.WaitForExit()
        # drain stderr — surfaces permission errors (cap_net_raw, sudo, etc.)
        while(-not $p.StandardError.EndOfStream){
            $l=$p.StandardError.ReadLine()
            if($l.Trim()){$Queue.Enqueue(@{Type='Error';Text="  $($l.ToUpper())"})}
        }
    }catch{$Queue.Enqueue(@{Type='Error';Text="MTR FAILED: $($_.Exception.Message.ToUpper())"})}
    # If binary ran but produced no hop data, fall back to native ICMP
    if($hopLines -eq 0){
        $Queue.Enqueue(@{Type='Dim';Text='  MTR BINARY PRODUCED NO OUTPUT — FALLING BACK TO NATIVE ICMP.'})
        $usedNative=$true
        NativeICMP $dest ([int]$cycles)
    }
}else{
    $Queue.Enqueue(@{Type='Dim';Text='  MTR BINARY NOT FOUND — USING NATIVE ICMP TRACEROUTE.'})
    $usedNative=$true
    NativeICMP $dest ([int]$cycles)
}
if($usedNative){$Queue.Enqueue(@{Type='Dim';Text='  NOTE: NATIVE MODE — RUNNING .\MTR.PS1 GIVES LIVE STATS.'})}
$Queue.Enqueue(@{Type='Dim';Text='ANALYSIS COMPLETE.'})
$Queue.Enqueue(@{Type='Done';Text=''})
'@
)

# ── Runspace management ───────────────────────────────────────────────────────
function script:Start-Mod([int]$idx, [string]$target) {
    Stop-Mod
    $q = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $script:Queue = $q

    $rs = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Queue', $q)
    $rs.SessionStateProxy.SetVariable('Target', $target)

    $ps = [Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:ModScripts[$idx])

    $script:RunRS = $rs
    $script:RunPS = $ps
    [void]$ps.BeginInvoke()
}

function script:Stop-Mod {
    if ($script:RunPS) { try { $script:RunPS.Stop() } catch {}; try { $script:RunPS.Dispose() } catch {}; $script:RunPS = $null }
    if ($script:RunRS) { try { $script:RunRS.Close() } catch {}; try { $script:RunRS.Dispose() } catch {}; $script:RunRS = $null }
    $script:Queue = $null
}

function script:DrainQ {
    if (-not $script:Queue) { return $false }
    $item  = $null
    $count = 0
    $done  = $false
    while ($count -lt 64 -and $script:Queue.TryDequeue([ref]$item)) {
        if ($item.Type -eq 'Done') { $done = $true; break }
        OAdd $item.Type $item.Text
        $count++
    }
    return $done
}

# ── Key handlers ─────────────────────────────────────────────────────────────
function script:MaxScroll { [Math]::Max(0, $script:Out.Count - $script:ViewH) }

function script:Key-Browse([System.ConsoleKeyInfo]$k) {
    switch ($k.Key) {
        'Q'        { return $true }
        'M'        { $script:Muted = -not $script:Muted
                     $script:StatusMsg = if ($script:Muted) { 'AUDIO MUTED.' } else { 'AUDIO UNMUTED.' } }
        { $_ -in 'UpArrow','K' } {
            if ($script:Sel -gt 0) { $script:Sel--; SndSel }
        }
        { $_ -in 'DownArrow','J' } {
            if ($script:Sel -lt $MODS.Count-1) { $script:Sel++; SndSel }
        }
        { $_ -in 'Enter','Tab' } {
            $script:AppMode  = 'Input'
            $script:StatusMsg = "INPUT MODE  $DIA  $($MODS[$script:Sel].Name)  $DIA  ENTER TARGET, THEN PRESS [ENTER]."
            SndInput
        }
        'PageUp'   { $script:AutoScroll = $false; $script:Scroll = [Math]::Max(0, $script:Scroll - $script:ViewH) }
        'PageDown' {
            $max = MaxScroll
            if ($script:Scroll -ge $max) { $script:AutoScroll = $true }
            else { $script:Scroll = [Math]::Min($max, $script:Scroll + $script:ViewH) }
        }
    }
    return $false
}

function script:Key-Input([System.ConsoleKeyInfo]$k) {
    if ($k.Key -eq 'Escape' -or $k.Key -eq 'Tab') {
        $script:AppMode = 'Browse'; $script:StatusMsg = 'AWAITING INSTRUCTION.'; SndCancel
    } elseif ($k.Key -eq 'Enter') {
        $t = $script:InputText.Trim()
        if (-not $t) {
            OAdd 'Error' 'NO TARGET SPECIFIED. ENTER TARGET AND RETRY.'
            SndErr
        } else {
            $ts = Get-Date -Format 'yyyy.MM.dd HH:mm:ss'
            OAdd 'Dim' ("$([string]::new([char]0x2501,3))  $ts  $([string]::new([char]0x2501,3))  $($MODS[$script:Sel].Name)  $([string]::new([char]0x2501,3))")
            $script:AutoScroll = $true
            $script:Scroll     = MaxScroll
            $script:AppMode    = 'Running'
            $script:StatusMsg  = "EXECUTING: $($MODS[$script:Sel].Name)  $DIA  [PGUP/DN] SCROLL  [M] MUTE  [Q] ABORT"
            $idx = $script:Sel
            $script:InputText  = ''
            SndStart
            Start-Mod $idx $t
        }
    } elseif ($k.Key -eq 'Backspace') {
        if ($script:InputText.Length -gt 0) { $script:InputText = $script:InputText.Substring(0, $script:InputText.Length-1); SndKey }
    } elseif ($k.KeyChar -and [char]::IsControl($k.KeyChar)) {
        if ($k.Key -eq 'U' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) {
            $script:InputText = ''; SndCancel
        }
    } elseif ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) {
        $script:InputText += $k.KeyChar; SndKey
    }
    return $false
}

function script:Key-Running([System.ConsoleKeyInfo]$k) {
    switch ($k.Key) {
        'Q'      { return $true }
        'M'      { $script:Muted = -not $script:Muted }
        'PageUp' { $script:AutoScroll = $false; $script:Scroll = [Math]::Max(0, $script:Scroll - $script:ViewH) }
        'PageDown' {
            $max = MaxScroll
            $script:Scroll = [Math]::Min($max, $script:Scroll + $script:ViewH)
            if ($script:Scroll -ge $max) { $script:AutoScroll = $true }
        }
    }
    return $false
}

# ── Main loop ─────────────────────────────────────────────────────────────────
# Enter alternate screen
[Console]::Write($ALT_ON)
[Console]::Write($HIDE_CUR)
[Console]::Clear()
[Console]::CursorVisible = $false
$script:DispRow = 0

OInit
SndBoot

$quit   = $false
$frameMs = 80

try {
    while (-not $quit) {
        # drain module output
        if ($script:AppMode -eq 'Running' -and $script:Queue) {
            $scanDone = DrainQ
            if ($scanDone) {
                Stop-Mod
                $script:AppMode  = 'Browse'
                $script:StatusMsg = 'ANALYSIS COMPLETE. AWAITING INSTRUCTION.'
                OAdd 'Dim' ([string]::new([char]0x2501, 50))
                SndDone
            }
        }

        $script:Tick++

        # render
        Render

        # key input (non-blocking poll within frame window)
        $t0 = [DateTime]::UtcNow
        do {
            if ([Console]::KeyAvailable) {
                $k    = [Console]::ReadKey($true)
                $quit = switch ($script:AppMode) {
                    'Browse'  { Key-Browse  $k }
                    'Input'   { Key-Input   $k }
                    'Running' { Key-Running $k }
                }
                if ($quit) { break }
            }
            Start-Sleep -Milliseconds 10
        } while (([DateTime]::UtcNow - $t0).TotalMilliseconds -lt $frameMs -and -not $quit)
    }
} finally {
    Stop-Mod
    [Console]::CursorVisible = $true
    [Console]::Write($SHOW_CUR)
    [Console]::Write($ALT_OFF)
}
