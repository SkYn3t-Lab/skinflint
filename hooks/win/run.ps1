# Builds skinflint.exe with the csc.exe that ships with the .NET Framework,
# then runs one hook with it. The hook line runs this only when the exe does
# not exist yet (its first run, or the first after an update); otherwise it
# loads the exe itself. Git Bash hands off here the same way (hooks/run.sh). BUILD is stamped by tools/stamp.sh from the source's hash, so an
# updated plugin never runs an old exe.
$sfHook = $args[0]
$sfData = $env:CLAUDE_PLUGIN_DATA
if (-not $sfData) { $sfData = $env:LOCALAPPDATA + '\skinflint' }
$sfExe = $sfData + '\skinflint-ce208e22532f.exe'
if (-not [IO.File]::Exists($sfExe)) {
  $sfCsc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if (-not [IO.File]::Exists($sfCsc)) { $sfCsc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
  [void][IO.Directory]::CreateDirectory($sfData)
  $sfTmp = $sfExe + '.' + $PID + '.tmp'
  & $sfCsc /nologo /optimize+ /target:exe "/out:$sfTmp" (Join-Path $PSScriptRoot 'skinflint.cs') > $null 2> $null
  if ([IO.File]::Exists($sfTmp)) {
    # Another hook may have finished the same build first; either copy works.
    try { [IO.File]::Move($sfTmp, $sfExe) } catch { [IO.File]::Delete($sfTmp) }
  }
}
if ([IO.File]::Exists($sfExe)) {
  [void][Reflection.Assembly]::LoadFile($sfExe)
  [void][Skinflint.Hook]::Main([string[]]@($sfHook))
}
# A top-level break ends the whole -Command of the hook line, so its fallback
# line never runs the hook a second time.
break
