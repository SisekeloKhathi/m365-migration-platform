<#
.SYNOPSIS
    Validates M365 migration readiness and compares source vs target
.DESCRIPTION
    Comprehensive validation of migration prerequisites and target environment
.PARAMETER SourceTenantId
    Source tenant ID for validation
.PARAMETER SourceClientId
    Source client ID for validation
.PARAMETER SourceClientSecret
    Source client secret for validation
.EXAMPLE
    .\Test-M365Migration.ps1 -SourceTenantId "tenant-id" -SourceClientId "client-id" -SourceClientSecret "secret"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceTenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceClientSecret,
    
    [Parameter()]
    [string]$ReportPath = "./reports",
    
    [Parameter()]
    [switch]$GenerateHTML
)

Write-Host "🔍 Starting Migration Validation..." -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Create reports directory if it doesn't exist
if (-not (Test-Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

# Import required modules
Import-Module Microsoft.Graph.Users -Force -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Groups -Force -ErrorAction SilentlyContinue

# Connect to source
try {
    $securePassword = ConvertTo-SecureString -String $SourceClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $SourceClientId, $securePassword
    Connect-MgGraph -TenantId $SourceTenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop
    Write-Host "✅ Connected to source tenant" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to source tenant: $_"
    return
}

# Get users
$users = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AccountEnabled, Mail, UserType
Write-Host "`n📋 Loaded $($users.Count) source users" -ForegroundColor Yellow

# Validate each user
$results = @()
$readyCount = 0
$needsAttentionCount = 0
$missingCount = 0
$errorCount = 0

Write-Host "`n🔍 Validating target environment..." -ForegroundColor Cyan

foreach ($user in $users) {
    Write-Host "`n  Validating: $($user.DisplayName)" -ForegroundColor White
    
    $result = [PSCustomObject]@{
        DisplayName = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        UserExistsInTarget = $false
        MailboxExists = $false
        AccountEnabled = $false
        HasLicense = $false
        Status = "Unknown"
        Message = ""
    }
    
    try {
        # Check if user exists
        $targetUser = Get-MgUser -Filter "userPrincipalName eq '$($user.UserPrincipalName)'" -ErrorAction SilentlyContinue
        
        if ($targetUser) {
            $result.UserExistsInTarget = $true
            Write-Host "    ✅ User exists in target: $($targetUser.UserPrincipalName)" -ForegroundColor Green
            
            # Check mailbox
            try {
                $mailbox = Get-MgUserMailboxSetting -UserId $targetUser.Id -ErrorAction SilentlyContinue
                if ($mailbox) {
                    $result.MailboxExists = $true
                    Write-Host "    📧 Mailbox verified: $($targetUser.UserPrincipalName)" -ForegroundColor Green
                } else {
                    Write-Host "    ⚠️ No mailbox found for: $($targetUser.UserPrincipalName)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "    ⚠️ Mailbox check failed: $_" -ForegroundColor Yellow
            }
            
            # Check account status
            $result.AccountEnabled = $targetUser.AccountEnabled
            if ($targetUser.AccountEnabled) {
                Write-Host "    ✅ Account enabled: $($targetUser.UserPrincipalName)" -ForegroundColor Green
            } else {
                Write-Host "    ⚠️ Account disabled: $($targetUser.UserPrincipalName)" -ForegroundColor Yellow
            }
            
            # Check license
            try {
                $licenses = Get-MgUserLicenseDetail -UserId $targetUser.Id -ErrorAction SilentlyContinue
                if ($licenses.Count -gt 0) {
                    $result.HasLicense = $true
                    Write-Host "    ✅ License assigned: $($licenses.Count) license(s)" -ForegroundColor Green
                } else {
                    Write-Host "    ⚠️ No license assigned" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "    ⚠️ License check failed: $_" -ForegroundColor Yellow
            }
            
            # Determine status
            if ($result.AccountEnabled -and $result.MailboxExists) {
                $result.Status = "Ready"
                $result.Message = "Ready for migration"
                $readyCount++
            } elseif ($result.AccountEnabled -and -not $result.MailboxExists) {
                $result.Status = "NeedsAttention"
                $result.Message = "Account enabled but no mailbox"
                $needsAttentionCount++
            } elseif (-not $result.AccountEnabled -and $result.MailboxExists) {
                $result.Status = "NeedsAttention"
                $result.Message = "Mailbox exists but account disabled"
                $needsAttentionCount++
            } else {
                $result.Status = "NeedsAttention"
                $result.Message = "Both account and mailbox need attention"
                $needsAttentionCount++
            }
        } else {
            $result.Status = "Missing"
            $result.Message = "User not found in target"
            $missingCount++
            Write-Host "    ❌ User not found in target: $($user.UserPrincipalName)" -ForegroundColor Red
        }
    } catch {
        $result.Status = "Error"
        $result.Message = "Error during validation: $_"
        $errorCount++
        Write-Host "    ❌ Error validating user: $_" -ForegroundColor Red
    }
    
    $results += $result
}

# Disconnect
Disconnect-MgGraph | Out-Null

# Generate summary
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summary = [PSCustomObject]@{
    Timestamp = Get-Date
    TotalUsers = $users.Count
    ReadyForMigration = $readyCount
    NeedsAttention = $needsAttentionCount
    Missing = $missingCount
    Errors = $errorCount
    Results = $results
}

Write-Host "`n📊 Validation Summary:" -ForegroundColor Cyan
Write-Host "  ✅ Ready for Migration: $readyCount" -ForegroundColor Green
Write-Host "  ⚠️ Needs Attention: $needsAttentionCount" -ForegroundColor Yellow
Write-Host "  ❌ Missing: $missingCount" -ForegroundColor Red
Write-Host "  ❌ Errors: $errorCount" -ForegroundColor Red

# Export CSV
$csvPath = Join-Path $ReportPath "Validation-$timestamp.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`n📊 Validation report saved to: $csvPath" -ForegroundColor Green

# Generate HTML report
if ($GenerateHTML) {
    $htmlPath = Join-Path $ReportPath "Validation-$timestamp.html"
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>M365 Migration Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .summary-card { padding: 15px; border-radius: 8px; text-align: center; }
        .summary-card.green { background: #d4edda; color: #155724; }
        .summary-card.yellow { background: #fff3cd; color: #856404; }
        .summary-card.red { background: #f8d7da; color: #721c24; }
        .summary-card.blue { background: #cce5ff; color: #004085; }
        .summary-card .number { font-size: 32px; font-weight: bold; }
        .summary-card .label { font-size: 14px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0078d4; color: white; padding: 10px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        .status-ready { color: #28a745; font-weight: bold; }
        .status-needs-attention { color: #ffc107; font-weight: bold; }
        .status-missing { color: #dc3545; font-weight: bold; }
        .status-error { color: #dc3545; font-weight: bold; }
        .timestamp { color: #666; font-size: 12px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 M365 Migration Validation Report</h1>
        <p>Generated: $(Get-Date)</p>
        
        <div class="summary">
            <div class="summary-card green">
                <div class="number">$readyCount</div>
                <div class="label">✅ Ready for Migration</div>
            </div>
            <div class="summary-card yellow">
                <div class="number">$needsAttentionCount</div>
                <div class="label">⚠️ Needs Attention</div>
            </div>
            <div class="summary-card red">
                <div class="number">$missingCount</div>
                <div class="label">❌ Missing</div>
            </div>
            <div class="summary-card blue">
                <div class="number">$($users.Count)</div>
                <div class="label">📋 Total Users</div>
            </div>
        </div>
        
        <h2>User Validation Details</h2>
        <table>
            <thead>
                <tr>
                    <th>Display Name</th>
                    <th>User Principal Name</th>
                    <th>Status</th>
                    <th>Account Enabled</th>
                    <th>Mailbox</th>
                    <th>License</th>
                    <th>Message</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($result in $results) {
        $statusClass = switch ($result.Status) {
            "Ready" { "status-ready" }
            "NeedsAttention" { "status-needs-attention" }
            "Missing" { "status-missing" }
            "Error" { "status-error" }
            default { "" }
        }
        
        $htmlContent += @"
                <tr>
                    <td>$($result.DisplayName)</td>
                    <td>$($result.UserPrincipalName)</td>
                    <td class="$statusClass">$($result.Status)</td>
                    <td>$($result.AccountEnabled)</td>
                    <td>$($result.MailboxExists)</td>
                    <td>$($result.HasLicense)</td>
                    <td>$($result.Message)</td>
                </tr>
"@
    }

    $htmlContent += @"
            </tbody>
        </table>
        <div class="timestamp">Report generated: $(Get-Date)</div>
    </div>
</body>
</html>
"@

    $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "📊 Validation report saved to: $htmlPath" -ForegroundColor Green
}

Write-Host "`n✅ Validation complete!" -ForegroundColor Green
Write-Host "📊 Results saved to: $csvPath" -ForegroundColor Green
