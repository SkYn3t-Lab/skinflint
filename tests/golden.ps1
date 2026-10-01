# Replays tests/cases/* through the Windows hooks (skinflint.exe, built here
# with the .NET Framework csc.exe) and compares stdout and the files left
# behind with each case's "expected" and "state", which golden.sh records.
# Needs only Windows PowerShell 5.1.
#   powershell -ExecutionPolicy Bypass -File tests\golden.ps1 [NAME...]
# Paths in output are normalised as golden.sh does (<SB>, <ROOT>), and the
# Windows status line command is mapped to the POSIX one it stands for.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$l1 = [Text.Encoding]::GetEncoding(28591)

# The exe name in run.ps1 must match the source (tools/stamp.sh keeps them in step).
$src = Join-Path $root 'hooks\win\skinflint.cs'
$sha = [Security.Cryptography.SHA256]::Create()
$id = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($src))) -replace '-', '').Substring(0, 12).ToLowerInvariant()
if (-not ([IO.File]::ReadAllText((Join-Path $root 'hooks\win\run.ps1'))).Contains("skinflint-$id.exe")) {
  Write-Output 'build stamp is stale: run sh tools/stamp.sh'
  exit 1
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('sf-golden-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($work)
$exe = Join-Path $work 'skinflint.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /optimize+ /target:exe "/out:$exe" $src | Out-Host
if (-not [IO.File]::Exists($exe)) { Write-Output 'build failed'; exit 1 }

function Slash([string]$p) { $p.Replace('\', '/') }

function Get-State([string]$sb) {
  $cfg = Join-Path $sb 'cfg'
  $rows = New-Object Collections.Generic.List[string]
  foreach ($f in (New-Object IO.DirectoryInfo($cfg)).GetFiles('*', 'AllDirectories')) {
    $rel = 'cfg/' + (Slash $f.FullName.Substring($cfg.Length + 1))
    $c = ''
    if ($rel.EndsWith('.mode') -or $rel.EndsWith('/stats')) { $c = $l1.GetString([IO.File]::ReadAllBytes($f.FullName)).Replace("`n", '\n') }
    $rows.Add($rel + ' ' + $f.Length + ' ' + $c)
  }
  $a = $rows.ToArray()
  [Array]::Sort($a, [StringComparer]::Ordinal)
  $s = ''
  foreach ($r in $a) { $s += $r + "`n" }
  return $s
}

$names = $args
if (-not $names -or $names.Count -eq 0) { $names = (Get-ChildItem (Join-Path $root 'tests\cases') -Directory | ForEach-Object Name) }
$names = [string[]]$names
[Array]::Sort($names, [StringComparer]::Ordinal)
$pass = 0; $fail = 0
$winCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File \\\"<ROOT>/hooks/win/statusline.ps1\\\"'
$posixCmd = 'sh \\\"<ROOT>/hooks/statusline.sh\\\"'
foreach ($name in $names) {
  $c = Join-Path $root "tests\cases\$name"
  $sb = Join-Path $work ('sb-' + $name)
  foreach ($d in 'cfg', 'xdg', 'work') { [void][IO.Directory]::CreateDirectory((Join-Path $sb $d)) }
  $setup = Join-Path $c 'setup'
  if ([IO.Directory]::Exists($setup)) { Copy-Item -Path (Join-Path $setup '*') -Destination $sb -Recurse -Force }

  $psi = New-Object Diagnostics.ProcessStartInfo $exe, ([IO.File]::ReadAllText((Join-Path $c 'hook')).Trim())
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = Join-Path $sb 'work'
  foreach ($k in @($psi.EnvironmentVariables.Keys)) { if ($k -like 'SKINFLINT_*' -or $k -eq 'CLAUDE_PLUGIN_DATA') { $psi.EnvironmentVariables.Remove($k) } }
  $psi.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = Join-Path $sb 'cfg'
  $psi.EnvironmentVariables['XDG_CONFIG_HOME'] = Join-Path $sb 'xdg'
  $psi.EnvironmentVariables['CLAUDE_PLUGIN_ROOT'] = $root
  $envFile = Join-Path $c 'env'
  if ([IO.File]::Exists($envFile)) {
    foreach ($line in [IO.File]::ReadAllLines($envFile)) {
      $i = $line.IndexOf('=')
      if ($i -gt 0) { $psi.EnvironmentVariables[$line.Substring(0, $i)] = $line.Substring($i + 1) }
    }
  }
  $p = [Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.BaseStream.CopyToAsync(($ms = New-Object IO.MemoryStream))
  $errTask = $p.StandardError.ReadToEndAsync()
  $in = [IO.File]::ReadAllBytes((Join-Path $c 'input.json'))
  $p.StandardInput.BaseStream.Write($in, 0, $in.Length)
  $p.StandardInput.Close()
  $p.WaitForExit()
  $outTask.Wait()
  $raw = $l1.GetString($ms.ToArray())
  $got = $raw.Replace((Slash $sb), '<SB>').Replace((Slash $root), '<ROOT>').Replace($winCmd, $posixCmd)
  # stats counts bytes saved, which depends on how long the sandbox path in
  # the output is: count it as if each occurrence were the 4 bytes of <SB>.
  $occ = ($raw.Length - $raw.Replace((Slash $sb), '').Length) / (Slash $sb).Length
  $st = Get-State $sb
  $m = [regex]::Match($st, '(?m)^(cfg/skinflint/stats \d+ saved )(\d+)')
  if ($m.Success) {
    $v = [long]$m.Groups[2].Value + $occ * ((Slash $sb).Length - 4)
    $st = $st.Substring(0, $m.Groups[2].Index) + $v + $st.Substring($m.Groups[2].Index + $m.Groups[2].Length)
  }
  $exp = $l1.GetString([IO.File]::ReadAllBytes((Join-Path $c 'expected')))
  $exs = $l1.GetString([IO.File]::ReadAllBytes((Join-Path $c 'state')))
  if ($got -ceq $exp -and $st -ceq $exs -and $p.ExitCode -eq 0) { $pass++ }
  else {
    $fail++
    Write-Output "FAIL $name"
    if ($p.ExitCode -ne 0) { Write-Output ('  exit code ' + $p.ExitCode) }
    if ($got -cne $exp) {
      $n = [Math]::Min($got.Length, $exp.Length); $i = 0
      while ($i -lt $n -and $got[$i] -eq $exp[$i]) { $i++ }
      $from = [Math]::Max(0, $i - 40)
      Write-Output ('  stdout differs at byte ' + $i)
      Write-Output ('    got ' + $got.Substring($from, [Math]::Min(120, $got.Length - $from)))
      Write-Output ('    exp ' + $exp.Substring($from, [Math]::Min(120, $exp.Length - $from)))
    }
    if ($st -cne $exs) { Write-Output '  state differs:'; Write-Output ('    got ' + $st); Write-Output ('    exp ' + $exs) }
    $e = $errTask.Result
    if ($e) { Write-Output ('  stderr: ' + $e) }
  }
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "$($pass + $fail) cases, $pass pass, $fail fail"
if ($fail -gt 0) { exit 1 }
