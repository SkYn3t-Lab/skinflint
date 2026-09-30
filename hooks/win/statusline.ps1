# Status line (Windows): token-miser's mode for this session and the output it has saved.
# Prints only fixed text and digits read from our own state files.
$ErrorActionPreference = 'SilentlyContinue'
$in = [Console]::In.ReadToEnd()
$base = $env:CLAUDE_CONFIG_DIR
if (-not $base) { $base = Join-Path $env:USERPROFILE '.claude' }
$dir = Join-Path $base 'token-miser'

$mode = ''
$m = [regex]::Match($in, '"session_id"\s*:\s*"([A-Za-z0-9_-]{1,128})"')
if ($m.Success) {
  $f = Join-Path $dir ('sessions\' + $m.Groups[1].Value + '.mode')
  if ([IO.File]::Exists($f)) { $mode = ([IO.File]::ReadAllText($f)).Trim().ToLowerInvariant() }
}
if ($mode -ne 'on' -and $mode -ne 'off') {
  $mode = 'on'
  if ("$env:TOKEN_MISER_DEFAULT_MODE".ToLowerInvariant() -eq 'off') { $mode = 'off' }
}

$extra = ''
$s = Join-Path $dir 'stats'
if ([IO.File]::Exists($s)) {
  $m = [regex]::Match([IO.File]::ReadAllText($s), '(?m)^saved ([0-9]{1,15})$')
  if ($m.Success) {
    $tok = [long]$m.Groups[1].Value / 4
    $tok = [math]::Floor($tok)
    if ($tok -ge 1000000) { $extra = ' saved ~' + [math]::Floor($tok / 1000000) + 'M tok' }
    elseif ($tok -ge 1000) { $extra = ' saved ~' + [math]::Floor($tok / 1000) + 'k tok' }
    elseif ($tok -gt 0) { $extra = ' saved ~' + $tok + ' tok' }
  }
}

$e = [char]27
if ($mode -eq 'on') { [Console]::Out.Write("$e[38;5;172m[TOKEN-MISER]$e[0m$extra") }
else { [Console]::Out.Write("$e[2m[token-miser off]$e[0m$extra") }
