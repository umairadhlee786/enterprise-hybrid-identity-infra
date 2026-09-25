<#
.SYNOPSIS
    Locks down NTFS and SMB share permissions on department file shares to their
    matching Active Directory security group.

.DESCRIPTION
    Windows evaluates NTFS (filesystem) and SMB (network share) permissions as two
    independent layers, applying whichever is more restrictive. New subfolders also
    inherit permissions from their parent by default. Both facts can quietly leave a
    "restricted" department share readable by every domain user unless explicitly
    corrected — which is exactly what this script does for each share:

      1. Grants the department's security group Change/Modify rights at both the
         NTFS and share layers.
      2. Disables inheritance on the folder and strips any inherited BUILTIN\Users
         entry that would otherwise grant broad access.

.PARAMETER ShareMap
    A hashtable mapping share name -> matching security group, e.g.
    @{ "Finance" = "SG-Finance"; "HR" = "SG-HR" }

.PARAMETER BasePath
    Root folder containing the department share folders (default: C:\Shares).

.NOTES
    Run locally on the file server (FS01). Domain Admins / SYSTEM / Administrators
    retain full control throughout — this script only removes overly broad
    BUILTIN\Users access, not administrative access.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$ShareMap,

    [string]$BasePath = "C:\Shares"
)

foreach ($shareName in $ShareMap.Keys) {

    $groupName = $ShareMap[$shareName]
    $folderPath = Join-Path $BasePath $shareName
    $domainGroup = "CORP\$groupName"

    if (-not (Test-Path $folderPath)) {
        Write-Warning "$folderPath does not exist — skipping $shareName"
        continue
    }

    # --- NTFS permission: grant the department group Modify rights ---
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $domainGroup, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl = Get-Acl $folderPath
    $acl.SetAccessRule($rule)
    Set-Acl $folderPath $acl

    # --- Remove inherited BUILTIN\Users access and stop future inheritance ---
    # icacls handles this more reliably than PowerShell's ACL cmdlets for
    # split/special-permission inherited entries.
    icacls $folderPath /inheritance:d | Out-Null
    icacls $folderPath /remove:g "BUILTIN\Users" | Out-Null

    # --- SMB share permission: match the NTFS-level access ---
    # (Share-level permissions are evaluated independently of NTFS — both must
    # allow access, since Windows applies whichever is more restrictive.)
    if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
        Grant-SmbShareAccess -Name $shareName -AccountName $domainGroup -AccessRight Change -Force | Out-Null
    }
    else {
        Write-Warning "Share '$shareName' not found — NTFS permissions set, but share-level access was skipped"
    }

    Write-Host "Locked down '$shareName' to $domainGroup (NTFS + share, inheritance removed)" -ForegroundColor Green
}

<#
.EXAMPLE
    $shares = @{
        "Finance" = "SG-Finance"
        "HR"      = "SG-HR"
        "Sales"   = "SG-Sales"
        "IT"      = "SG-IT"
    }
    .\Set-SharePermissions.ps1 -ShareMap $shares
#>
