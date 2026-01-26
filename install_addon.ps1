# Attendance Exporter - Installation Script
# Copies the addon to your World of Warcraft AddOns directory

Write-Host "Attendance Exporter - Installation Script" -ForegroundColor Cyan
Write-Host "=" * 50

# Source directory (current directory where script is located)
$sourceDir = $PSScriptRoot

# Verify required addon files exist
$tocFile = Join-Path $sourceDir "AttendanceExporter.toc"
$luaFile = Join-Path $sourceDir "AttendanceExporter.lua"

if (-not (Test-Path $tocFile)) {
    Write-Host "Error: AttendanceExporter.toc not found in current directory." -ForegroundColor Red
    Write-Host "Please run this script from the directory containing the addon files." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $luaFile)) {
    Write-Host "Error: AttendanceExporter.lua not found in current directory." -ForegroundColor Red
    Write-Host "Please run this script from the directory containing the addon files." -ForegroundColor Yellow
    exit 1
}

# Possible WoW installation paths
$possiblePaths = @(
    "${env:ProgramFiles(x86)}\World of Warcraft\_retail_\Interface\AddOns",
    "${env:ProgramFiles}\World of Warcraft\_retail_\Interface\AddOns",
    "$env:USERPROFILE\Documents\WoW\_retail_\Interface\AddOns"
)

$targetDir = $null

# Try to find WoW installation
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $targetDir = $path
        Write-Host "Found WoW installation at: $path" -ForegroundColor Green
        break
    }
}

if (-not $targetDir) {
    Write-Host "`nCould not find World of Warcraft installation automatically." -ForegroundColor Yellow
    Write-Host "Please provide the path to your AddOns directory:" -ForegroundColor Yellow
    $targetDir = Read-Host "Path"
    $targetDir = $targetDir.Trim('"')
    
    if (-not (Test-Path $targetDir)) {
        Write-Host "Error: Directory not found: $targetDir" -ForegroundColor Red
        exit 1
    }
}

$destination = Join-Path $targetDir "AttendanceExporter"

Write-Host "`nSource: $sourceDir" -ForegroundColor Cyan
Write-Host "Destination: $destination" -ForegroundColor Cyan

# Check if addon already exists
if (Test-Path $destination) {
    Write-Host "`nWarning: AttendanceExporter already exists at destination." -ForegroundColor Yellow
    $overwrite = Read-Host "Overwrite? (Y/N)"
    if ($overwrite -ne "Y" -and $overwrite -ne "y") {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
    
    # Remove existing addon
    try {
        Remove-Item -Path $destination -Recurse -Force
        Write-Host "Removed existing addon." -ForegroundColor Green
    } catch {
        Write-Host "Error removing existing addon: $_" -ForegroundColor Red
        exit 1
    }
}

# Copy addon files
try {
    Write-Host "`nCopying addon files..." -ForegroundColor Cyan
    
    # Create destination folder if it doesn't exist
    if (-not (Test-Path $destination)) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }
    
    # Copy all files from source directory to destination
    Get-ChildItem -Path $sourceDir -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $destination -Force
        Write-Host "  Copied: $($_.Name)" -ForegroundColor Gray
    }
    
    Write-Host "`nSuccessfully installed AttendanceExporter!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Restart World of Warcraft or type /reload in-game" -ForegroundColor White
    Write-Host "2. Join a raid group to see the 'Take Attendance' button" -ForegroundColor White
} catch {
    Write-Host "`nError copying files: $_" -ForegroundColor Red
    exit 1
}
