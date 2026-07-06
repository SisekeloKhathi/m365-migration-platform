param(
    [string]$ReportsPath = "./reports",
    [string]$OutputPath = "./reports"
)

Write-Host "📊 Starting Migration Assessment..." -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Find the latest CSV files
$userFiles = Get-ChildItem -Path $ReportsPath -Filter "Users-*.csv" | Sort-Object LastWriteTime -Descending
$groupFiles = Get-ChildItem -Path $ReportsPath -Filter "Groups-*.csv" | Sort-Object LastWriteTime -Descending
$mailboxFiles = Get-ChildItem -Path $ReportsPath -Filter "Mailboxes-*.csv" | Sort-Object LastWriteTime -Descending

if ($userFiles.Count -eq 0) {
    Write-Error "❌ No user data found. Please run discovery first."
    exit 1
}

# Load the data
$users = Import-Csv $userFiles[0].FullName
$groups = @()
if ($groupFiles.Count -gt 0) {
    $groups = Import-Csv $groupFiles[0].FullName
}
$mailboxes = @()
if ($mailboxFiles.Count -gt 0) {
    $mailboxes = Import-Csv $mailboxFiles[0].FullName
}

Write-Host "`n📋 Data loaded:" -ForegroundColor Yellow
Write-Host "  Users: $($users.Count)" -ForegroundColor Green
Write-Host "  Groups: $($groups.Count)" -ForegroundColor Green
Write-Host "  Mailboxes: $($mailboxes.Count)" -ForegroundColor Green

# Assessment checks
Write-Host "`n🔍 Running assessments..." -ForegroundColor Yellow

$issues = @()
$warnings = @()
$recommendations = @()

# 1. Check for duplicate users
$duplicates = $users | Group-Object UserPrincipalName | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    $issues += "Found $($duplicates.Count) duplicate users"
    $recommendations += "Remove duplicate user accounts before migration"
}

# 2. Check for guest users
$guestUsers = $users | Where-Object { $_.UserType -eq "Guest" }
if ($guestUsers) {
    $warnings += "Found $($guestUsers.Count) guest users"
    $recommendations += "Review guest users - they may need special handling"
}

# 3. Check disabled users
$disabledUsers = $users | Where-Object { $_.AccountEnabled -eq "False" }
if ($disabledUsers) {
    $warnings += "Found $($disabledUsers.Count) disabled users"
    $recommendations += "Review disabled users - decide if they should be migrated"
}

# 4. Check mailbox readiness
$mailboxCount = $users.Count
if ($mailboxCount -gt 0) {
    $mailboxReady = $mailboxes.Count
    if ($mailboxReady -eq 0) {
        $warnings += "No mailbox data found"
        $recommendations += "Ensure mailboxes are accessible in the source tenant"
    }
}

# 5. Check group readiness
if ($groups.Count -gt 0) {
    $securityGroups = $groups | Where-Object { $_.SecurityEnabled -eq "True" }
    $m365Groups = $groups | Where-Object { $_.GroupTypes -like "*Unified*" }
    Write-Host "  ✅ Security Groups: $($securityGroups.Count)" -ForegroundColor Green
    Write-Host "  ✅ M365 Groups: $($m365Groups.Count)" -ForegroundColor Green
} else {
    Write-Host "  ℹ️ No groups found" -ForegroundColor Yellow
}

# Calculate readiness score
$totalChecks = 5
$passedChecks = 5

if ($duplicates) { $passedChecks-- }
if ($guestUsers.Count -gt 0) { $passedChecks-- }
if ($disabledUsers.Count -gt 0) { $passedChecks-- }
if ($mailboxReady -eq 0 -and $mailboxCount -gt 0) { $passedChecks-- }

$readinessScore = [math]::Round(($passedChecks / $totalChecks) * 100)
$readinessLevel = if ($readinessScore -ge 80) { "🟢 HIGH" } elseif ($readinessScore -ge 60) { "🟡 MEDIUM" } else { "🔴 LOW" }

Write-Host "`n📈 Readiness Score: $readinessScore% ($readinessLevel)" -ForegroundColor Cyan

# Generate HTML report
$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>M365 Migration Assessment</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { border-bottom: 3px solid #0078D4; padding-bottom: 20px; margin-bottom: 30px; }
        .header h1 { color: #0078D4; margin: 0; }
        .header .subtitle { color: #666; font-size: 14px; }
        .score-card { background: #f8f9fa; border-radius: 8px; padding: 20px; margin: 20px 0; display: inline-block; min-width: 200px; }
        .score-number { font-size: 48px; font-weight: bold; color: #0078D4; }
        .score-label { color: #666; font-size: 14px; }
        .section { margin: 30px 0; padding: 20px; background: #f8f9fa; border-radius: 8px; }
        .section h2 { color: #333; margin-top: 0; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: bold; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #0078D4; color: white; }
        tr:hover { background: #f1f1f1; }
        .issue-list { list-style: none; padding: 0; }
        .issue-list li { padding: 8px 12px; margin: 5px 0; background: white; border-radius: 4px; border-left: 4px solid #ffc107; }
        .issue-list .error { border-left-color: #dc3545; }
        .issue-list .warning { border-left-color: #ffc107; }
        .recommendation { background: #d1ecf1; padding: 10px 15px; border-radius: 4px; margin: 5px 0; border-left: 4px solid #17a2b8; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Microsoft 365 Migration Assessment</h1>
            <div class="subtitle">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</div>
            <div class="subtitle">Tenant: $($tenantId)</div>
        </div>

        <div style="display: flex; gap: 20px; flex-wrap: wrap; margin: 20px 0;">
            <div class="score-card">
                <div class="score-number">$readinessScore%</div>
                <div class="score-label">Readiness Score</div>
                <div style="margin-top: 5px;"><span class="badge $($readinessLevel.Split(' ')[1])">$readinessLevel</span></div>
            </div>
            <div class="score-card">
                <div class="score-number">$($users.Count)</div>
                <div class="score-label">Total Users</div>
            </div>
            <div class="score-card">
                <div class="score-number">$($groups.Count)</div>
                <div class="score-label">Total Groups</div>
            </div>
            <div class="score-card">
                <div class="score-number">$($mailboxes.Count)</div>
                <div class="score-label">Mailboxes</div>
            </div>
        </div>

        <div class="section">
            <h2>📋 Summary</h2>
            <table>
                <tr><th>Metric</th><th>Count</th><th>Status</th></tr>
                <tr><td>Total Users</td><td>$($users.Count)</td><td><span class="badge badge-success">✓</span></td></tr>
                <tr><td>Guest Users</td><td>$($guestUsers.Count)</td><td><span class="badge $(if($guestUsers.Count -gt 0){'badge-warning'}else{'badge-success'})">$(if($guestUsers.Count -gt 0){'⚠️'}else{'✓'})</span></td></tr>
                <tr><td>Disabled Users</td><td>$($disabledUsers.Count)</td><td><span class="badge $(if($disabledUsers.Count -gt 0){'badge-warning'}else{'badge-success'})">$(if($disabledUsers.Count -gt 0){'⚠️'}else{'✓'})</span></td></tr>
                <tr><td>Groups</td><td>$($groups.Count)</td><td><span class="badge badge-success">✓</span></td></tr>
                <tr><td>Mailboxes</td><td>$($mailboxes.Count)</td><td><span class="badge badge-success">✓</span></td></tr>
            </table>
        </div>

        <div class="section">
            <h2>⚠️ Issues & Warnings</h2>
            $(if ($issues.Count -gt 0 -or $warnings.Count -gt 0) {
                "<ul class='issue-list'>"
                foreach ($issue in $issues) {
                    "<li class='error'>❌ $issue</li>"
                }
                foreach ($warning in $warnings) {
                    "<li class='warning'>⚠️ $warning</li>"
                }
                "</ul>"
            } else {
                "<p style='color: green;'>✅ No critical issues found. Your tenant is ready for migration!</p>"
            })
        </div>

        <div class="section">
            <h2>💡 Recommendations</h2>
            $(if ($recommendations.Count -gt 0) {
                foreach ($rec in $recommendations) {
                    "<div class='recommendation'>💡 $rec</div>"
                }
            } else {
                "<p style='color: green;'>✅ No specific recommendations. Your tenant appears ready for migration.</p>"
            })
        </div>

        <div class="section">
            <h2>👥 Users</h2>
            <table>
                <tr><th>Display Name</th><th>User Principal Name</th><th>Type</th><th>Status</th></tr>
                $(foreach ($user in $users) {
                    "<tr>
                        <td>$($user.DisplayName)</td>
                        <td>$($user.UserPrincipalName)</td>
                        <td>$($user.UserType)</td>
                        <td><span class='badge $(if($user.AccountEnabled -eq "True"){"badge-success"}else{"badge-danger"})'>$(if($user.AccountEnabled -eq "True"){"✓ Active"}else{"Disabled"})</span></td>
                    </tr>"
                })
            </table>
        </div>

        <div class="section">
            <h2>🔍 Next Steps</h2>
            <ol>
                <li><strong>Phase 3:</strong> Prepare Target Environment - Create users, groups, and licenses in the target tenant</li>
                <li><strong>Phase 4:</strong> Pilot Migration - Test with 5 users</li>
                <li><strong>Phase 5:</strong> Full Migration - Execute all batches</li>
                <li><strong>Phase 6:</strong> Validation - Compare source and target</li>
            </ol>
        </div>

        <div class="footer">
            Generated by M365 Migration Platform v1.0<br>
            © 2026 - All Rights Reserved
        </div>
    </div>
</body>
</html>
"@

# Save the HTML report
$htmlFile = "$OutputPath/Assessment-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $htmlFile -Encoding UTF8

Write-Host "`n✅ Assessment complete!" -ForegroundColor Green
Write-Host "📊 Report saved to: $htmlFile" -ForegroundColor Yellow

# Open the report in browser
Start-Process $htmlFile

# Also export a summary JSON
$summary = [PSCustomObject]@{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TotalUsers = $users.Count
    GuestUsers = $guestUsers.Count
    DisabledUsers = $disabledUsers.Count
    TotalGroups = $groups.Count
    TotalMailboxes = $mailboxes.Count
    ReadinessScore = $readinessScore
    ReadinessLevel = $readinessLevel
    Issues = $issues
    Warnings = $warnings
    Recommendations = $recommendations
}
$summary | ConvertTo-Json -Depth 3 | Out-File -FilePath "$OutputPath/AssessmentSummary.json" -Encoding UTF8

Write-Host "📊 Assessment Summary saved to: $OutputPath/AssessmentSummary.json" -ForegroundColor Yellow
Write-Host "`n🎉 Assessment phase complete!" -ForegroundColor Green
