param([Parameter(Mandatory)][string[]]$Plugin, [int]$Rounds = 15)
# Time every hook of several Claude Code plugins on Windows, the way Claude
# Code runs them: with Git Bash when it is installed, else with PowerShell.
# Each -Plugin is NAME=DIR. Each plugin's own hook commands come from its
# manifest, with ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_DATA} filled in,
# and run from Git Bash (bash -c), Windows PowerShell 5.1 and PowerShell 7
# (-Command). Every call gets its own configuration directory, prepared
# outside the timing: prompt and subagent calls start from the state the
# plugin's own session-start hook left, tool-output calls from an empty one.
# Rounds are interleaved so load on the machine falls on every variant alike.
# Prints medians in milliseconds; "-" is no hook for that event, "!" a call
# that failed (non-zero exit). A hook that ran but printed nothing (by design,
# for some plugins) is listed under the table.
#
#   powershell -ExecutionPolicy Bypass -File benchmarks\speed.ps1 -Plugin a=C:\a,b=C:\b

$ErrorActionPreference = 'Stop'
$base = Join-Path $env:TEMP ('sf-speed-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$data = Join-Path $base 'data'
[void][IO.Directory]::CreateDirectory($data)
$bash = 'C:\Program Files\Git\bin\bash.exe'; if (-not (Test-Path $bash)) { $bash = $null }
$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
# Quote one argument by the Windows command-line rules (as Node and Claude
# Code do): backslashes are literal except before a quote, where they double.
function Quote-Arg([string]$a) {
  $sb = New-Object Text.StringBuilder; [void]$sb.Append('"'); $n = 0
  foreach ($ch in $a.ToCharArray()) {
    if ($ch -eq '\') { $n++; continue }
    if ($ch -eq '"') { [void]$sb.Append('\', 2 * $n + 1); [void]$sb.Append('"') } else { [void]$sb.Append('\', $n); [void]$sb.Append($ch) }
    $n = 0
  }
  [void]$sb.Append('\', 2 * $n); [void]$sb.Append('"'); $sb.ToString()
}
$shells = [ordered]@{}
if ($bash) { $shells['Git Bash'] = { param($c) @($bash, ('-c ' + (Quote-Arg $c))) } }
$shells['PowerShell 5.1'] = { param($c) @('powershell.exe', ('-NoProfile -NonInteractive -Command ' + (Quote-Arg $c))) }
if ($pwsh) { $shells['PowerShell 7'] = { param($c) @($pwsh, ('-NoProfile -NonInteractive -Command ' + (Quote-Arg $c))) } }

function Get-Hooks([string]$root) {
  $m = Get-Content -Raw (Join-Path $root '.claude-plugin\plugin.json') | ConvertFrom-Json
  $h = $m.hooks
  if ($h -is [string]) { $h = Get-Content -Raw (Join-Path $root $h) | ConvertFrom-Json }
  if ($null -eq $h) { $h = Get-Content -Raw (Join-Path $root 'hooks\hooks.json') | ConvertFrom-Json }
  if ($h.PSObject.Properties.Name -contains 'hooks') { $h = $h.hooks }
  return $h
}
function Get-Command2($hooks, [string]$ev, [string]$key, [string]$root) {
  if (-not ($hooks.PSObject.Properties.Name -contains $ev)) { return $null }
  foreach ($e in $hooks.$ev) {
    $mt = $e.matcher
    if (-not $mt -or $mt -eq '*' -or $key -match ('^(' + $mt + ')$')) {
      $r = $root.Replace('\', '/')
      return $e.hooks[0].command.Replace('${CLAUDE_PLUGIN_ROOT}', $r).Replace('${CLAUDE_PLUGIN_DATA}', $data.Replace('\', '/'))
    }
  }
  return $null
}
function Invoke-Hook([string]$exe, [string]$argLine, [string]$stdin, [string]$cfg, [string]$root) {
  $psi = New-Object Diagnostics.ProcessStartInfo $exe
  $psi.Arguments = $argLine
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $cfg
  $psi.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = $cfg
  $psi.EnvironmentVariables['CLAUDE_PLUGIN_ROOT'] = $root
  $psi.EnvironmentVariables['CLAUDE_PLUGIN_DATA'] = $data
  $psi.EnvironmentVariables['CLAUDE_PROJECT_DIR'] = $cfg
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.StandardInput.Write($stdin); $p.StandardInput.Close(); $p.WaitForExit()
  return @{ Out = $o.Result; Rc = $p.ExitCode }
}
function New-Cfg([string]$from) {
  $d = Join-Path $base ('cfg-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
  if ($from) { Copy-Item -LiteralPath $from -Destination $d -Recurse } else { [void][IO.Directory]::CreateDirectory($d) }
  [IO.File]::WriteAllText((Join-Path $d '.chisle-active'), 'on')
  return $d
}

$log30 = ((1..480 | ForEach-Object { '2026-09-30T12:00:00Z INFO compiling module ' + $_ + ' of the build: ok' }) -join '\n')
$rows3000 = ((1..3000 | ForEach-Object { 'row ' + $_ }) -join '\n')
function Tool([string]$text, [string]$sid) { '{"session_id":"' + $sid + '","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"toolu_' + $sid + '","tool_input":{"command":"make"},"tool_response":{"stdout":"' + $text + '","stderr":""}}' }
$startup = '{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}'
$cases = @(
  @('startup', 'SessionStart', 'startup', $startup, $true),
  @('prompt', 'UserPromptSubmit', '', '{"session_id":"s1","hook_event_name":"UserPromptSubmit","prompt":"how do I reverse a list in Python?"}', $true),
  @('subagent', 'SubagentStart', '', '{"session_id":"s1","hook_event_name":"SubagentStart","agent_type":"general-purpose"}', $true),
  @('small output', 'PostToolUse', 'Bash', (Tool 'hi' 's2'), $false),
  @('3000 lines', 'PostToolUse', 'Bash', (Tool $rows3000 's3'), $false),
  @('30 KB log', 'PostToolUse', 'Bash', (Tool $log30 's4'), $false)
)

$plugins = [ordered]@{}
foreach ($p in $Plugin) { $n, $d = $p.Split('=', 2); $plugins[$n] = @{ Root = $d; Hooks = (Get-Hooks $d) } }
# The session state each plugin's own SessionStart hook leaves, per shell.
$tpl = @{}
foreach ($n in $plugins.Keys) {
  foreach ($s in $shells.Keys) {
    $cfg = New-Cfg $null
    $c = Get-Command2 $plugins[$n].Hooks 'SessionStart' 'startup' $plugins[$n].Root
    if ($c) { $a = & $shells[$s] $c; [void](Invoke-Hook $a[0] $a[1] $startup $cfg $plugins[$n].Root) }
    $tpl["$n|$s"] = $cfg
  }
}

$result = [ordered]@{}
$silent = New-Object Collections.Generic.List[string]
foreach ($case in $cases) {
  $col, $ev, $key, $payload, $must = $case
  $variants = [ordered]@{}
  foreach ($n in $plugins.Keys) {
    $c = Get-Command2 $plugins[$n].Hooks $ev $key $plugins[$n].Root
    foreach ($s in $shells.Keys) {
      $v = "$n, $s"
      if (-not $result.Contains($v)) { $result[$v] = [ordered]@{} }
      if (-not $c) { $result[$v][$col] = '-'; continue }
      $from = if ($ev -eq 'UserPromptSubmit' -or $ev -eq 'SubagentStart') { $tpl["$n|$s"] } else { $null }
      $variants[$v] = @{ Args = (& $shells[$s] $c); From = $from; Root = $plugins[$n].Root; Samples = (New-Object Collections.Generic.List[double]) }
    }
  }
  $bad = @{}
  foreach ($v in $variants.Keys) {
    $x = $variants[$v]; $cfg = New-Cfg $x.From
    $r = Invoke-Hook $x.Args[0] $x.Args[1] $payload $cfg $x.Root
    $bad[$v] = $r.Rc -ne 0
    if (-not $bad[$v] -and $must -and $r.Out.Trim().Length -eq 0) { $silent.Add("$v $col") }
  }
  $keys = @($variants.Keys)
  for ($round = 0; $round -lt $Rounds; $round++) {
    for ($j = 0; $j -lt $keys.Count; $j++) {
      $v = $keys[($j + $round) % $keys.Count]; $x = $variants[$v]
      $cfg = New-Cfg $x.From
      $x.Samples.Add((Measure-Command { [void](Invoke-Hook $x.Args[0] $x.Args[1] $payload $cfg $x.Root) }).TotalMilliseconds)
    }
  }
  foreach ($v in $keys) {
    $a = $variants[$v].Samples.ToArray(); [Array]::Sort($a)
    $result[$v][$col] = ('{0:N0}' -f $a[[int][math]::Floor($a.Length / 2)]) + $(if ($bad[$v]) { '!' } else { '' })
  }
}

$cols = @($cases | ForEach-Object { $_[0] })
'| ms, median of ' + $Rounds + ' | ' + ($cols -join ' | ') + ' |'
'|---|' + ('--:|' * $cols.Count)
foreach ($v in $result.Keys) { '| ' + $v + ' | ' + (($cols | ForEach-Object { $result[$v][$_] }) -join ' | ') + ' |' }
if ($silent.Count) { ''; 'Ran but printed nothing: ' + ($silent -join ', ') }
Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
