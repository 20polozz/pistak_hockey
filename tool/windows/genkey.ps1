# Creates the pistak. release signing key ONCE.
# - Never overwrites an existing key (losing/replacing it breaks every update).
# - Reads the passwords from android\key.properties (local file, git-ignored).
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$props = Join-Path $root 'android\key.properties'
if (-not (Test-Path $props)) { Write-Host 'android\key.properties not found'; exit 2 }
$kv = @{}
Get-Content $props | ForEach-Object { if ($_ -match '^\s*([^=#]+)=(.*)$') { $kv[$matches[1].Trim()] = $matches[2].Trim() } }
$store = Join-Path (Join-Path $root 'android\app') $kv['storeFile']
if (Test-Path $store) { Write-Host "Key already exists: $store (not touched)"; exit 0 }
$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
if (-not (Test-Path $keytool)) { $keytool = 'keytool' }
& $keytool -genkeypair -v -keystore $store -storetype PKCS12 -keyalg RSA -keysize 2048 `
  -validity 10000 -alias $kv['keyAlias'] -storepass $kv['storePassword'] -keypass $kv['keyPassword'] `
  -dname 'CN=pistak, OU=apps, O=pistak, C=ES'
exit $LASTEXITCODE
