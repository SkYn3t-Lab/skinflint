# Builds token-miser.exe with the csc.exe that ships with the .NET Framework,
# then runs one hook with it. The hook line runs this only when the exe does
# not exist yet (its first run, or the first after an update); otherwise it
# loads the exe itself. Git Bash hands off here the same way (hooks/run.sh). BUILD is stamped by tools/stamp.sh from the source's hash, so an
# updated plugin never runs an old exe.
$tmHook = $args[0]
$tmData = $env:CLAUDE_PLUGIN_DATA
if (-not $tmData) { $tmData = $env:LOCALAPPDATA + '\token-miser' }
$tmExe = $tmData + '\token-miser-5b4c500ee24b.exe'
if (-not [IO.File]::Exists($tmExe)) {
  $tmCsc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if (-not [IO.File]::Exists($tmCsc)) { $tmCsc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
  [void][IO.Directory]::CreateDirectory($tmData)
  $tmTmp = $tmExe + '.' + $PID + '.tmp'
  & $tmCsc /nologo /optimize+ /target:exe "/out:$tmTmp" (Join-Path $PSScriptRoot 'token-miser.cs') > $null 2> $null
  if ([IO.File]::Exists($tmTmp)) {
    # Another hook may have finished the same build first; either copy works.
    try { [IO.File]::Move($tmTmp, $tmExe) } catch { [IO.File]::Delete($tmTmp) }
  }
}
if ([IO.File]::Exists($tmExe)) {
  [void][Reflection.Assembly]::LoadFile($tmExe)
  [void][TokenMiser.Hook]::Main([string[]]@($tmHook))
}
# A top-level break ends the whole -Command of the hook line, so its fallback
# line never runs the hook a second time.
break
