$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$shareHeader = Join-Path $repoRoot 'windows\flutter\ephemeral\.plugin_symlinks\share_plus\windows\share_plus_windows_plugin.h'
$vectorHeader = Join-Path $repoRoot 'windows\flutter\ephemeral\.plugin_symlinks\share_plus\windows\vector.h'
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
Write-Utf8NoBom $shareHeader $shareText

# share_plus's WinRT vector helper needs the Foundation collection ABI
# declarations as well as the STL/WRL headers. The previous patch only added
# vector + implements.h, which left ElementType/RuntimeClassT undefined.
if (-not (Test-Path $vectorHeader)) {
    throw "share_plus vector.h not found: $vectorHeader. Run flutter pub get first."
}
$vectorText = [System.IO.File]::ReadAllText($vectorHeader)
$requiredIncludes = @(
    '#include <ivectorchangedeventargs.h>',
    '#include <windows.foundation.collections.h>',
    '#include <algorithm>',
    '#include <iterator>',
    '#include <utility>',
    '#include <vector>',
    '#include <wrl/implements.h>'
)
foreach ($includeLine in $requiredIncludes) {
    $escaped = [regex]::Escape($includeLine)
    if ($vectorText -notmatch "(?m)^\s*$escaped\s*$") {
        $vectorText = [regex]::Replace(
            $vectorText,
            '(?m)^\s*#pragma once\s*',
            ("#pragma once`r`n" + $includeLine + "`r`n"),
            1
        )
    }
}
foreach ($includeLine in $requiredIncludes) {
    if ($vectorText -notmatch "(?m)^\s*" + [regex]::Escape($includeLine) + "\s*$") {
        throw "Could not add required include to share_plus vector.h: $includeLine"
    }
}
Write-Utf8NoBom $vectorHeader $vectorText

# MSVC's strict conformance mode rejects the currently published
# flutter_secure_storage_windows GetValueKey member definition (C4596).
# Override /permissive- for this plugin target only; don't weaken the whole app.
$secureCmake = Join-Path $repoRoot 'windows\flutter\ephemeral\.plugin_symlinks\flutter_secure_storage_windows\windows\CMakeLists.txt'
if (-not (Test-Path $secureCmake)) {
    throw "flutter_secure_storage_windows CMakeLists.txt not found: $secureCmake. Run flutter pub get first."
}
$secureCmakeText = [System.IO.File]::ReadAllText($secureCmake)
if ($secureCmakeText -notmatch '(?m)target_compile_options\(\$\{PLUGIN_NAME\} PRIVATE /permissive\)') {
    $anchor = 'apply_standard_settings(${PLUGIN_NAME})'
    if (-not $secureCmakeText.Contains($anchor)) {
        throw 'Could not locate flutter_secure_storage_windows CMake target settings anchor.'
    }
    $secureCmakeText = $secureCmakeText.Replace(
        $anchor,
        $anchor + "`r`nif(MSVC)`r`n  target_compile_options(`${PLUGIN_NAME} PRIVATE /permissive)`r`nendif()"
    )
}
Write-Utf8NoBom $secureCmake $secureCmakeText

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
if ($changed -or $alreadyPatched -or $knownModernForm) {
    Write-Utf8NoBom $secureCpp $secureText
}
Write-Host 'Windows plugin compatibility patches applied.'
