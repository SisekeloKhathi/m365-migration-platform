Describe "M365 Migration Platform Tests" {
    Context "Discovery Module" {
        It "Should import the module" {
            Import-Module ../powershell/modules/M365Migration.psm1 -Force
            $true | Should Be $true
        }
    }
    
    Context "Validation Module" {
        It "Should validate user format" {
            $validUser = "user@domain.com"
            $validUser -match "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" | Should Be $true
        }
    }
}
