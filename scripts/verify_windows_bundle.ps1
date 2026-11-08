param([Parameter(Mandatory=$true)][string]$Archive)
$ErrorActionPreference = "Stop"
$bundle = Join-Path $env:TEMP ("fileinfra-bundle-" + [guid]::NewGuid().ToString("N"))
$app = $null
try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $bundle
    $runtimes = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
    foreach ($name in @("fileinfra.exe", "dufs.dll") + $runtimes) {
        if (-not (Test-Path (Join-Path $bundle $name))) { throw "Missing bundled $name" }
    }
    python scripts/verify_dufs_ffi.py (Join-Path $bundle "dufs.dll")
    if ($LASTEXITCODE -ne 0) { throw "Packaged dufs FFI verification failed" }
    $app = Start-Process -FilePath (Join-Path $bundle "fileinfra.exe") -WorkingDirectory $bundle -PassThru
    Start-Sleep -Seconds 5
    $app.Refresh()
    if ($app.HasExited) { throw "Packaged FileInfra exited during startup: $($app.ExitCode)" }
    foreach ($name in $runtimes) {
        $module = $app.Modules | Where-Object { $_.ModuleName -ieq $name } | Select-Object -First 1
        if (-not $module -or $module.FileName -ine (Join-Path $bundle $name)) {
            throw "FileInfra did not load its packaged runtime $name"
        }
    }
    Write-Host "Packaged FileInfra starts and loads all three app-local MSVC runtime DLLs"
} finally {
    if ($app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force }
    Remove-Item -LiteralPath $bundle -Recurse -Force -ErrorAction SilentlyContinue
}
