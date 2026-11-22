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
if ($shareText -notmatch '(?m)^\s*#include\s*[<"]wrl\.h[>"]') {
    if ($shareText -match '(?m)^\s*#include\s*[<"]Windows\.h[>"]') {
        $shareText = [regex]::Replace($shareText, '(?m)^(\s*#include\s*[<"]Windows\.h[>"].*)$', ('$1' + "`r`n" + '#include <wrl.h>'), 1)
    } elseif ($shareText -match '(?m)^\s*#include\s*[<"]windows\.h[>"]') {
        $shareText = [regex]::Replace($shareText, '(?m)^(\s*#include\s*[<"]windows\.h[>"].*)$', ('$1' + "`r`n" + '#include <wrl.h>'), 1)
    } else {
        throw 'share_plus header has no Windows.h include anchor; refusing an unsafe edit.'
    }
}
$shareText = $shareText.Replace('static std::wstring SharePlusWindowsPlugin::Utf16FromUtf8', 'static std::wstring Utf16FromUtf8')
if ($shareText -notmatch '(?m)^\s*#include\s*[<"]wrl\.h[>"]') {
    throw 'WRL include was not added to share_plus header.'
}
Write-Utf8NoBom $shareHeader $shareText
Write-Host "Patched $shareHeader"

if (-not (Test-Path $secureCpp)) {
    throw "flutter_secure_storage Windows source not found: $secureCpp. Run flutter pub get first."
}
$secureText = [System.IO.File]::ReadAllText($secureCpp)
$oldForms = @(
    'std::string target_name(CW2A(pcred->TargetName));',
    'std::string target_name = CW2A(pcred->TargetName);'
)
$newForm = "CW2A target_name_ansi(pcred->TargetName);`r`nstd::string target_name(static_cast<LPCSTR>(target_name_ansi));"
$changed = $false
foreach ($oldForm in $oldForms) {
    if ($secureText.Contains($oldForm)) {
        $secureText = $secureText.Replace($oldForm, $newForm)
        $changed = $true
        break
    }
}
$alreadyPatched = $secureText.Contains('std::string target_name(static_cast<LPCSTR>(target_name_ansi));')
$knownModernForm = $secureText -match 'std::string\s+target_name\s*\(\s*static_cast\s*<\s*LPCSTR\s*>\s*\('
if (-not $changed -and -not $alreadyPatched -and -not $knownModernForm) {
    Write-Warning 'No known CW2A target_name conversion found. Leaving source unchanged so the compiler can report the actual incompatibility.'
} else {
    Write-Utf8NoBom $secureCpp $secureText
    Write-Host "Checked $secureCpp"
}
