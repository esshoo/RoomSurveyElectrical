$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$obsoleteFiles = @(
    'RoomSurveyElectrical/SmartProjectEmbedding.swift'
)

foreach ($relativePath in $obsoleteFiles) {
    $fullPath = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Force
        Write-Host "Removed obsolete file: $relativePath"
    } else {
        Write-Host "Already clean: $relativePath"
    }
}

Write-Host 'Obsolete source cleanup completed.'
