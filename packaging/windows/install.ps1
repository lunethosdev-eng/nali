param(
  [Parameter(Mandatory = $true)]
  [string]$Archive
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Archive)) {
  throw "No se encontró el archivo: $Archive"
}

$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Nali'
$TempDir = Join-Path $env:TEMP ("nali-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
try {
  Expand-Archive -LiteralPath $Archive -DestinationPath $TempDir -Force
  $Exe = Get-ChildItem -Path $TempDir -Filter 'nali.exe' -Recurse | Select-Object -First 1
  if (-not $Exe) { throw 'El ZIP no contiene nali.exe.' }
  if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -Path (Join-Path $Exe.Directory.FullName '*') -Destination $InstallDir -Recurse -Force
  Write-Host "Nali se instaló en $InstallDir"
  Write-Host "Ejecuta: & `"$InstallDir\nali.exe`""
} finally {
  Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
