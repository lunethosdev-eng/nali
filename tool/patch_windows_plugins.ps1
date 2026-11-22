$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$shareHeader = Join-Path $repoRoot 'windows\flutter\ephemeral\.plugin_symlinks\share_plus\windows\share_plus_windows_plugin.h'
$secureCpp = Join-Path $repoRoot 'windows\flutter\ephemeral\.plugin_symlinks\flutter_secure_storage_windows\windows\flutter_secure_storage_windows_plugin.cpp'

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path $shareHeader)) {
    throw "share_plus Windows header not found: $shareHeader. Run flutter pub get first."
}
$shareText = [System.IO.File]::ReadAllText($shareHeader)
$wrlIndex = $shareText.IndexOf('#include <wrl.h>')
$foundationIndex = $shareText.IndexOf('#include <windows.applicationmodel.datatransfer.h>')
if ($wrlIndex -lt 0 -or $foundationIndex -lt 0 -or $wrlIndex -gt $foundationIndex) {
    $shareText = $shareText.Replace('#include <Windows.h>', '#include <Windows.h>' + "`r`n" + '#include <wrl.h>')
}
$shareText = $shareText.Replace(
    'static std::wstring SharePlusWindowsPlugin::Utf16FromUtf8',
    'static std::wstring Utf16FromUtf8'
)
$wrlIndex = $shareText.IndexOf('#include <wrl.h>')
$foundationIndex = $shareText.IndexOf('#include <windows.applicationmodel.datatransfer.h>')
if ($wrlIndex -lt 0 -or $foundationIndex -lt 0 -or $wrlIndex -gt $foundationIndex -or
    $shareText -match 'static std::wstring SharePlusWindowsPlugin::Utf16FromUtf8') {
    throw 'Could not apply share_plus Windows C++ compatibility patch.'
}
Write-Utf8NoBom $shareHeader $shareText
Write-Host "Patched $shareHeader"

if (-not (Test-Path $secureCpp)) {
    throw "flutter_secure_storage Windows source not found: $secureCpp. Run flutter pub get first."
}
$secureText = [System.IO.File]::ReadAllText($secureCpp)
$old = 'std::string target_name(CW2A(pcred->TargetName));'
$new = 'CW2A target_name_ansi(pcred->TargetName);' + "`r`n" + 'std::string target_name(static_cast<LPCSTR>(target_name_ansi));'
if ($secureText.Contains($old)) {
    $secureText = $secureText.Replace($old, $new)
} elseif ($secureText -notmatch 'std::string target_name\(static_cast<LPCSTR>\(target_name_ansi\)\);') {
    throw 'Could not apply flutter_secure_storage Windows ATL conversion patch.'
}
Write-Utf8NoBom $secureCpp $secureText
Write-Host "Patched $secureCpp"
