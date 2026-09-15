<#
.SYNOPSIS
    Bulk-provisions Active Directory user accounts from a CSV file.

.DESCRIPTION
    Reads a CSV of new hires (FirstName, LastName, Department, JobTitle) and, for each
    row, creates a matching AD user account, places it in the correct department OU,
    and adds it to the matching department security group. Designed to replace manual,
    one-at-a-time account creation for bulk onboarding scenarios.

.PARAMETER CsvPath
    Path to the input CSV. Expected columns: FirstName, LastName, Department, JobTitle.

.NOTES
    Assumes an OU structure of:
        OU=<Department>,OU=Staff,OU=HQ,DC=corp,DC=local   (Finance / HR / Sales)
        OU=IT,OU=HQ,DC=corp,DC=local                       (IT — sits outside Staff)
    and a matching security group named "SG-<Department>" inside each OU.

    New accounts are created with a temporary password and forced to change it
    at first logon — do not use this temporary password as a long-term credential.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath
)

Import-Module ActiveDirectory

$domain = "corp.local"
$tempPassword = "ChangeMe123!"   # Temporary only — ChangePasswordAtLogon forces an immediate reset

$users = Import-Csv -Path $CsvPath

foreach ($user in $users) {

    # Route to the correct OU. IT sits directly under HQ rather than under Staff,
    # so it needs its own path rather than following the department-name pattern.
    $ouPath = "OU=$($user.Department),OU=Staff,OU=HQ,DC=corp,DC=local"
    if ($user.Department -eq "IT") {
        $ouPath = "OU=IT,OU=HQ,DC=corp,DC=local"
    }

    # Build a username as first-initial + surname, lowercased (e.g. "Alice Nguyen" -> "anguyen")
    $samAccountName = ($user.FirstName.Substring(0, 1) + $user.LastName).ToLower()
    $upn = "$samAccountName@$domain"
    $displayName = "$($user.FirstName) $($user.LastName)"

    try {
        New-ADUser `
            -Name $displayName `
            -GivenName $user.FirstName `
            -Surname $user.LastName `
            -SamAccountName $samAccountName `
            -UserPrincipalName $upn `
            -Path $ouPath `
            -Title $user.JobTitle `
            -Department $user.Department `
            -AccountPassword (ConvertTo-SecureString $tempPassword -AsPlainText -Force) `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -ErrorAction Stop

        Add-ADGroupMember -Identity "SG-$($user.Department)" -Members $samAccountName

        Write-Host "Created $displayName ($samAccountName) in $ouPath, added to SG-$($user.Department)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create $displayName ($samAccountName): $_"
    }
}
