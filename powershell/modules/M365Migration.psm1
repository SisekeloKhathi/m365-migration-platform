# M365Migration.psm1 - Using Graph SDK Directly
function Connect-M365Tenant {
    param([Parameter(Mandatory)]$TenantId, [Parameter(Mandatory)]$ClientId, [Parameter(Mandatory)]$ClientSecret)
    try {
        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $ClientId, $secureSecret
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
        Write-Host "✅ Connected to tenant: $TenantId" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "❌ Failed to connect: $_"
        return $false
    }
}

function Get-GraphData {
    param([Parameter(Mandatory)]$Uri)
    
    $allResults = @()
    $nextLink = $Uri
    
    do {
        try {
            # Use Invoke-MgGraphRequest which handles authentication automatically
            $response = Invoke-MgGraphRequest -Uri $nextLink -Method Get
            
            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }
            
            $nextLink = $response.'@odata.nextLink'
            Start-Sleep -Milliseconds 200
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 429) {
                $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                $delay = if ($retryAfter) { [int]$retryAfter } else { 60 }
                Write-Warning "⚠️ Rate limited. Waiting $delay seconds..."
                Start-Sleep -Seconds $delay
            }
            else {
                throw $_
            }
        }
    } while ($nextLink)
    
    return $allResults
}

function Export-MigrationReport {
    param($ReportName, $Data, $Path = "./reports")
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = "$ReportName-$timestamp.csv"
    $fullPath = Join-Path $Path $fileName
    if ($Data) {
        $Data | Export-Csv -Path $fullPath -NoTypeInformation
        Write-Host "📊 Report saved: $fullPath" -ForegroundColor Yellow
    }
    else {
        Write-Host "⚠️ No data to export for $ReportName" -ForegroundColor Yellow
    }
    return $fullPath
}

Export-ModuleMember -Function @('Connect-M365Tenant','Get-GraphData','Export-MigrationReport')
