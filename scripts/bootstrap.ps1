Write-Host "🚀 M365 Migration Platform Bootstrap" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

Write-Host "`n📋 Installing Microsoft Graph module..." -ForegroundColor Yellow
Install-Module Microsoft.Graph -Scope CurrentUser -Force -SkipPublisherCheck

Write-Host "`n📁 Creating additional directories..." -ForegroundColor Yellow
$dirs = @("./reports", "./logs", "./dashboards", "./docs", "./tests")
foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) { 
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  ✅ Created: $dir" -ForegroundColor Green
    }
}

Write-Host "`n🔐 Setting up .env file..." -ForegroundColor Yellow
if (!(Test-Path "./.env")) {
    Copy-Item "./.env.example" "./.env" -Force
    Write-Host "  ✅ Created .env file" -ForegroundColor Green
    Write-Host "  ⚠️ Edit .env with your tenant credentials!" -ForegroundColor Yellow
}

Write-Host "`n🎉 Bootstrap complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Edit .env with your credentials: notepad .env"
Write-Host "2. Run discovery: .\powershell\discovery\Get-M365Inventory.ps1"
