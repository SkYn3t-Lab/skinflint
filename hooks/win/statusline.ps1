# Status line (Windows): skinflint's mode for this session and the output it has saved.
# Prints only fixed text and digits read from our own state files.
$ErrorActionPreference = 'SilentlyContinue'
$in = [Console]::In.ReadToEnd()
$base = $env:CLAUDE_CONFIG_DIR
if (-not $base) { $base = Join-Path $env:USERPROFILE '.claude' }
$dir = Join-Path $base 'skinflint'

$mode = ''
$m = [regex]::Match($in, '"session_id"\s*:\s*"([A-Za-z0-9_-]{1,128})"')
if ($m.Success) {
  $f = Join-Path $dir ('sessions\' + $m.Groups[1].Value + '.mode')
  if ([IO.File]::Exists($f)) { $mode = ([IO.File]::ReadAllText($f)).Trim().ToLowerInvariant() }
}
if ($mode -ne 'on' -and $mode -ne 'off') {
  $mode = 'on'
  if ("$env:SKINFLINT_DEFAULT_MODE".ToLowerInvariant() -eq 'off') { $mode = 'off' }
}

$extra = ''
$s = Join-Path $dir 'stats'
if ([IO.File]::Exists($s)) {
  # Net of everything: tool output trimmed, plus the estimated saving on
  # replies (reply * 51 / 49, SPEC.md 2.1), minus what the plugin injected.
  $t = [IO.File]::ReadAllText($s)
  $m = [regex]::Match($t, '(?m)^saved ([0-9]{1,15})$')
  if ($m.Success) {
    $reply = [long]0; $inj = [long]0
    $r = [regex]::Match($t, '(?m)^reply ([0-9]{1,15})$')
    if ($r.Success) { $reply = [long]$r.Groups[1].Value }
    $r = [regex]::Match($t, '(?m)^injected ([0-9]{1,15})$')
    if ($r.Success) { $inj = [long]$r.Groups[1].Value }
    $tok = [math]::Floor(([long]$m.Groups[1].Value + [math]::Floor($reply * 51 / 49) - $inj) / 4)
    if ($tok -ge 1000000) { $extra = ' saved ~' + [math]::Floor($tok / 1000000) + 'M tok' }
    elseif ($tok -ge 1000) { $extra = ' saved ~' + [math]::Floor($tok / 1000) + 'k tok' }
    elseif ($tok -gt 0) { $extra = ' saved ~' + $tok + ' tok' }
  }
}

$e = [char]27
if ($mode -eq 'on') { [Console]::Out.Write("$e[38;5;172m[SKINFLINT]$e[0m$extra") }
else { [Console]::Out.Write("$e[2m[skinflint off]$e[0m$extra") }
