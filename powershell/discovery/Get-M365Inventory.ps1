param($TenantId, $ClientId, $ClientSecret, $OutputPath = "./reports")

# Connect using the credential
$securePassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential -ArgumentList $ClientId, $securePassword
Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome

Write-Host "🔍 Starting inventory discovery..." -ForegroundColor Cyan
if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

Write-Host "📥 Collecting users..." -ForegroundColor Yellow

# Use Get-MgUser which handles pagination automatically
$users = Get-MgUser -All -Select "id,displayName,userPrincipalName,mail,userType,accountEnabled,createdDateTime" -ErrorAction Stop

# Clean and export users
$cleanUsers = $users | ForEach-Object {
    [PSCustomObject]@{
        Id = $_.Id
        DisplayName = $_.DisplayName
        UserPrincipalName = $_.UserPrincipalName
        Mail = $_.Mail
        UserType = $_.UserType
        AccountEnabled = $_.AccountEnabled
        CreatedDateTime = $_.CreatedDateTime
    }
}
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$cleanUsers | Export-Csv -Path "$OutputPath/Users-$timestamp.csv" -NoTypeInformation
Write-Host "  ✅ Found $($cleanUsers.Count) users" -ForegroundColor Green

# Show users
$cleanUsers | Select-Object DisplayName, UserPrincipalName, UserType | Format-Table -AutoSize

Write-Host "📥 Collecting groups..." -ForegroundColor Yellow
$groups = Get-MgGroup -All -Select "id,displayName,mail,groupTypes,visibility,securityEnabled,createdDateTime" -ErrorAction SilentlyContinue
if ($groups) {
    $cleanGroups = $groups | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.Id
            DisplayName = $_.DisplayName
            Mail = $_.Mail
            GroupTypes = ($_.GroupTypes -join ',')
            Visibility = $_.Visibility
            SecurityEnabled = $_.SecurityEnabled
            CreatedDateTime = $_.CreatedDateTime
        }
    }
    $cleanGroups | Export-Csv -Path "$OutputPath/Groups-$timestamp.csv" -NoTypeInformation
    Write-Host "  ✅ Found $($cleanGroups.Count) groups" -ForegroundColor Green
} else {
    Write-Host "  ✅ Found 0 groups" -ForegroundColor Green
}

Write-Host "📥 Collecting mailboxes..." -ForegroundColor Yellow
$mailboxes = $users | ForEach-Object {
    [PSCustomObject]@{
        UserPrincipalName = $_.UserPrincipalName
        DisplayName = $_.DisplayName
        MailboxGuid = $_.Id
    }
}
$mailboxes | Export-Csv -Path "$OutputPath/Mailboxes-$timestamp.csv" -NoTypeInformation
Write-Host "  ✅ Found $($mailboxes.Count) mailboxes" -ForegroundColor Green

Write-Host "📥 Collecting SharePoint sites..." -ForegroundColor Yellow
try {
    $sites = Get-MgSite -All -Select "id,displayName,webUrl,createdDateTime" -ErrorAction Stop
    $cleanSites = $sites | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.Id
            DisplayName = $_.DisplayName
            WebUrl = $_.WebUrl
            CreatedDateTime = $_.CreatedDateTime
        }
    }
    $cleanSites | Export-Csv -Path "$OutputPath/Sites-$timestamp.csv" -NoTypeInformation
    Write-Host "  ✅ Found $($cleanSites.Count) sites" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ Could not retrieve sites: $_" -ForegroundColor Yellow
}

Write-Host "📥 Collecting Teams..." -ForegroundColor Yellow
try {
    $teams = Get-MgGroup -All -Filter "resourceProvisioningOptions/Any(x:x eq 'Team')" -Select "id,displayName,visibility,createdDateTime" -ErrorAction Stop
    $cleanTeams = $teams | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.Id
            DisplayName = $_.DisplayName
            Visibility = $_.Visibility
            CreatedDateTime = $_.CreatedDateTime
        }
    }
    $cleanTeams | Export-Csv -Path "$OutputPath/Teams-$timestamp.csv" -NoTypeInformation
    Write-Host "  ✅ Found $($cleanTeams.Count) teams" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ Could not retrieve teams: $_" -ForegroundColor Yellow
}

Write-Host "🎉 Discovery complete!" -ForegroundColor Green

$summary = [PSCustomObject]@{
    Users = $cleanUsers.Count
    Groups = if ($groups) { $groups.Count } else { 0 }
    Mailboxes = $mailboxes.Count
    Sites = if ($sites) { $sites.Count } else { 0 }
    Teams = if ($teams) { $teams.Count } else { 0 }
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}
$summary | Export-Csv -Path "$OutputPath/DiscoverySummary.csv" -NoTypeInformation
Write-Host "📈 Summary: $($summary | ConvertTo-Json)" -ForegroundColor Cyan

Disconnect-MgGraph
