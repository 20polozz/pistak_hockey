# PISTAK local build runner (Windows).
#
# Lets the Claude session drive Flutter on this PC WITHOUT a free-form shell:
# it only executes the fixed, whitelisted actions below. Jobs are files in
# .runner\queue\<id>.job containing one action name (+ optional test path).
# Output goes to .runner\out\<id>.log and the exit code to <id>.done.
# Close the window (or queue the action "stop") to end it.

$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$queue = Join-Path $root '.runner\queue'
$out = Join-Path $root '.runner\out'
New-Item -ItemType Directory -Force -Path $queue, $out | Out-Null
Set-Location $root

$actions = @{
  'doctor'   = 'flutter --version && flutter doctor -v'
  'create'   = 'flutter create . --project-name pistak --org cat.pistak --platforms android,web'
  'pubget'   = 'flutter pub get'
  'upgrade'  = 'flutter pub upgrade'
  'outdated' = 'flutter pub outdated'
  'codegen'  = 'dart run build_runner build'
  'l10n'     = 'flutter gen-l10n'
  'analyze'  = 'flutter analyze'
  'format'   = 'dart format lib test'
  'test'     = 'flutter test'
  'apk'      = 'flutter build apk --release'
  'apkdebug' = 'flutter build apk --debug'
  'web'      = 'flutter build web --release --no-web-resources-cdn'
  'devices'  = 'flutter devices'
  'clean'    = 'flutter clean'
}

Write-Host "PISTAK runner listening in $queue (Ctrl+C or close window to stop)"
while ($true) {
  $job = Get-ChildItem -Path $queue -Filter '*.job' -ErrorAction SilentlyContinue |
         Sort-Object Name | Select-Object -First 1
  if (-not $job) { Start-Sleep -Seconds 2; continue }

  $id = [IO.Path]::GetFileNameWithoutExtension($job.Name)
  $parts = ((Get-Content $job.FullName -Raw) -as [string]).Trim() -split '\s+'
  Remove-Item $job.FullName -Force
  $name = $parts[0]
  $log = Join-Path $out "$id.log"
  $done = Join-Path $out "$id.done"

  if ($name -eq 'stop') { Set-Content $done '0'; break }
  if (-not $actions.ContainsKey($name)) {
    Set-Content $log "Unknown action: $name"; Set-Content $done '127'; continue
  }
  $cmd = $actions[$name]
  if ($name -eq 'test' -and $parts.Count -gt 1) {
    if ($parts[1] -match '^test[\\/][A-Za-z0-9_\\/\.]+$') { $cmd = "$cmd $($parts[1])" }
  }
  Write-Host "[$(Get-Date -Format HH:mm:ss)] $id : $cmd"
  cmd.exe /c "$cmd > `"$log`" 2>&1"
  $code = $LASTEXITCODE
  Set-Content $done "$code"
  Write-Host "    -> exit $code"
}
