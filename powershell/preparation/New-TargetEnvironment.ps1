param(
    [string]$SourceTenantId,
    [string]$SourceClientId,
    [string]$SourceClientSecret,
    [string]$TargetTenantId = $SourceTenantId,
    [string]$TargetClientId = $SourceClientId,
    [string]$TargetClientSecret = $SourceClientSecret,
    [string]$ReportsPath = "./reports"
)

Write-Host "🏗️ Starting Target Environment Preparation..." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

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

# Prepare target
Write-Host "`n🏗️ Preparing target environment..." -ForegroundColor Yellow

$createdUsers = @()
$existingUsers = @()

foreach ($user in $users) {
    Write-Host "  Processing: $($user.DisplayName)" -ForegroundColor Gray
    
    # Check if user exists in target
    try {
        $existingUser = Get-MgUser -Filter "userPrincipalName eq '$($user.UserPrincipalName)'" -ErrorAction SilentlyContinue
        
        if ($existingUser) {
            Write-Host "    ⚠️ User already exists: $($user.UserPrincipalName)" -ForegroundColor Yellow
            $existingUsers += $user
        } else {
            # Create user in target
            $password = "TempPass@$(Get-Random -Minimum 1000 -Maximum 9999)"
            $passwordProfile = @{
                Password = $password
                ForceChangePasswordNextSignIn = $true
            }
            
            $newUserParams = @{
                DisplayName = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                PasswordProfile = $passwordProfile
                AccountEnabled = $true
                MailNickname = $user.UserPrincipalName.Split('@')[0]
            }
            
            # Add mail if available
            if ($user.Mail) {
                $newUserParams.Mail = $user.Mail
            }
            
            $newUser = New-MgUser @newUserParams -ErrorAction Stop
            Write-Host "    ✅ Created user: $($user.UserPrincipalName)" -ForegroundColor Green
            $createdUsers += $newUser
        }
    } catch {
        Write-Host "    ❌ Failed to create user: $_" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n📊 Target Preparation Summary:" -ForegroundColor Cyan
Write-Host "  ✅ Created: $($createdUsers.Count) users" -ForegroundColor Green
Write-Host "  ⚠️ Already existed: $($existingUsers.Count) users" -ForegroundColor Yellow

# Save results
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    CreatedUsers = $createdUsers.Count
    ExistingUsers = $existingUsers.Count
    TotalProcessed = $users.Count
}
$results | ConvertTo-Json | Out-File -FilePath "$ReportsPath/TargetPreparation-$timestamp.json" -Encoding UTF8

Write-Host "`n✅ Target preparation complete!" -ForegroundColor Green
Write-Host "📊 Results saved to: $ReportsPath/TargetPreparation-$timestamp.json" -ForegroundColor Yellow

Disconnect-MgGraph
