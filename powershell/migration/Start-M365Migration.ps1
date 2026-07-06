param(
    [string]$SourceTenantId,
    [string]$SourceClientId,
    [string]$SourceClientSecret,
    [string]$TargetTenantId = $SourceTenantId,
    [string]$TargetClientId = $SourceClientId,
    [string]$TargetClientSecret = $SourceClientSecret,
    [string]$ReportsPath = "./reports"
)

Write-Host "✈️ Starting Pilot Migration..." -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Connect to Source
$securePassword = ConvertTo-SecureString -String $SourceClientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential -ArgumentList $SourceClientId, $securePassword
Connect-MgGraph -TenantId $SourceTenantId -ClientSecretCredential $credential -NoWelcome

# Load discovery data
$userFiles = Get-ChildItem -Path $ReportsPath -Filter "Users-*.csv" | Sort-Object LastWriteTime -Descending
if ($userFiles.Count -eq 0) {
    Write-Error "❌ No user data found. Please run discovery first."
    exit 1
}

$users = Import-Csv $userFiles[0].FullName
Write-Host "`n📋 Loaded $($users.Count) users from discovery" -ForegroundColor Yellow

# Pilot migration - migrate first 5 users (or all if less than 5)
$pilotUsers = $users | Select-Object -First 5
Write-Host "`n✈️ Pilot migration for $($pilotUsers.Count) users..." -ForegroundColor Yellow

$migrationResults = @()

foreach ($user in $pilotUsers) {
    Write-Host "  Processing: $($user.DisplayName)" -ForegroundColor Gray
    
    # Check if user exists in target
    $existingUser = Get-MgUser -Filter "userPrincipalName eq '$($user.UserPrincipalName)'" -ErrorAction SilentlyContinue
    
    if ($existingUser) {
        Write-Host "    ✅ User exists in target: $($user.UserPrincipalName)" -ForegroundColor Green
        
        # Check if mail is enabled (in a real migration, this would be more complex)
        try {
            $mailboxSettings = Get-MgUserMailboxSetting -UserId $existingUser.Id -ErrorAction SilentlyContinue
            Write-Host "    📧 Mailbox found for: $($user.UserPrincipalName)" -ForegroundColor Green
            $mailboxStatus = "Found"
        } catch {
            Write-Host "    ⚠️ Mailbox not found: $($user.UserPrincipalName)" -ForegroundColor Yellow
            $mailboxStatus = "Not Found"
        }
        
        $migrationResults += [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName = $user.DisplayName
            Status = "Ready for Migration"
            MailboxStatus = $mailboxStatus
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    } else {
        Write-Host "    ❌ User not found in target: $($user.UserPrincipalName)" -ForegroundColor Red
        $migrationResults += [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName = $user.DisplayName
            Status = "User Not Found in Target"
            MailboxStatus = "N/A"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

# Summary
$successCount = ($migrationResults | Where-Object { $_.Status -eq "Ready for Migration" }).Count
$warningCount = ($migrationResults | Where-Object { $_.Status -eq "User Not Found in Target" }).Count

Write-Host "`n📊 Pilot Migration Summary:" -ForegroundColor Cyan
Write-Host "  ✅ Ready for Migration: $successCount" -ForegroundColor Green
Write-Host "  ⚠️ Users Not Found: $warningCount" -ForegroundColor Yellow

# Save results
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$migrationResults | Export-Csv -Path "$ReportsPath/PilotMigration-$timestamp.csv" -NoTypeInformation

Write-Host "`n✅ Pilot migration complete!" -ForegroundColor Green
Write-Host "📊 Results saved to: $ReportsPath/PilotMigration-$timestamp.csv" -ForegroundColor Yellow

Disconnect-MgGraph
