# Enterprise Hybrid Identity & Infrastructure — Phase 1: On-Prem Foundation

**Part of a larger portfolio project.** This is the on-prem identity and file services layer of a two-project portfolio built to demonstrate help desk, cloud, and networking skills for IT/networking roles. This phase will later be extended with an M365 + Entra ID + Intune hybrid identity layer, and connected to Azure via a site-to-site VPN.

## Problem Statement

In any organization beyond a handful of people, user accounts, permissions, and computer configuration can't be managed one machine at a time. This project builds the classic Windows-based answer to that problem: a centralized directory (Active Directory) that lets any employee log into any company machine, a policy system (Group Policy) that pushes configuration and restrictions to everyone automatically, and centralized file storage where access is governed by group membership rather than per-user, per-file permissions.

This is, in miniature, exactly what day-one help desk and MSP work looks like: onboarding new starters, resetting passwords, fixing "I can't access the shared drive" tickets, and pushing policy changes across a fleet of machines from one place.

## Architecture

```
                        VMnet2 — isolated host-only network
                            192.168.10.0/24 (no internet)

        ┌───────────────────────┐
        │        DC01 (.10)     │
        │  Windows Server 2022  │
        │   Standard (Core)     │
        │   AD DS + DNS         │
        │   Domain: corp.local  │
        └───────────┬───────────┘
                     │  AD auth + DNS
          ┌──────────┴──────────┐
          │                     │
┌─────────▼──────────┐ ┌────────▼─────────────┐
│     FS01 (.20)      │ │     CLIENT01 (.30)   │
│ Windows Server 2022 │ │    Windows 11 Pro    │
│  Standard (Core)    │ │  RSAT admin console  │
│   File Server       │ │  (manages DC01/FS01  │
│ (Finance/HR/Sales/IT)│ │   remotely)          │
└─────────┬────────────┘ └───────────┬──────────┘
          └──────────SMB shares──────┘
```

### Organizational Unit structure

```
corp.local
└── HQ
    ├── Staff
    │   ├── Finance   (SG-Finance)
    │   ├── HR        (SG-HR)
    │   └── Sales     (SG-Sales)
    ├── IT            (SG-IT)
    └── Computers
        ├── Workstations
        └── Servers
```

Staff is split by department for precise GPO targeting; IT sits outside Staff so it can be exempted from staff-wide restrictions without any explicit filtering — it's exempt purely by OU placement. Computers is separated from user OUs since computer-targeted and user-targeted policies serve different purposes.

## Environment & Tools

| Component | Role | OS | IP |
|---|---|---|---|
| DC01 | Domain Controller, DNS | Windows Server 2022 Standard (Core) | 192.168.10.10 |
| FS01 | File Server | Windows Server 2022 Standard (Core) | 192.168.10.20 |
| CLIENT01 | Admin workstation (RSAT) | Windows 11 Pro | 192.168.10.30 |

**Hypervisor:** VMware Workstation Pro (free for personal use)
**Network:** Isolated host-only virtual network (VMnet2), no internet access by design — a temporary NAT adapter was added only to download RSAT via Windows Update, then removed

## What Was Built

- **Active Directory forest** (`corp.local`) with a department-based OU structure
- **Security groups** (`SG-Finance`, `SG-HR`, `SG-Sales`, `SG-IT`) mapped to departments, used for both file permissions and GPO targeting
- **CSV-driven PowerShell bulk provisioning script** — creates users from a CSV and automatically routes each to the correct OU and security group based on department
- **File shares** for each department, with matching NTFS and SMB share permissions locked to the correct security group (see [Challenges](#challenges--troubleshooting) — this took two attempts to get fully correct)
- **Three Group Policy Objects:**
  - Domain-wide password policy (min length 10, complexity enabled, 90-day max age, 5-password history)
  - Per-department drive mapping (Finance/HR/Sales), linked at the OU level and targeted at the matching security group as a second layer of certainty
  - Control Panel restriction, linked to the `Staff` OU — inherited by Finance/HR/Sales automatically, with IT exempt purely by sitting outside that OU

## Design Decisions

- **Server Core, not Desktop Experience, for DC01 and FS01.** Smaller footprint, closer to how production domain controllers and file servers are actually run, and forces genuine comfort with PowerShell and remote administration rather than click-through GUI management.
- **Remote administration via RSAT from CLIENT01,** rather than logging into the servers directly — mirrors how a real sysadmin's day-to-day workflow looks.
- **Deliberately kept the AD environment on-prem (not in Azure)** to preserve a meaningful "hybrid" story for the later phase of this project, where this network gets connected to Azure via site-to-site VPN.
- **Security groups placed inside their matching OU**, not in a flat container — keeps the directory readable: browsing to the Finance OU shows both the Finance staff and the group that governs their access.
- **NTFS and SMB share permissions locked down independently at both layers**, rather than leaving the default wide-open share permissions in place — reflects a defense-in-depth approach, not just "it works."

## PowerShell Automation

See [`/scripts`](./scripts):
- `New-BulkUsers.ps1` — CSV-driven user provisioning, auto-assigns OU and group membership by department
- `Set-SharePermissions.ps1` — hardens NTFS and share-level permissions on the department shares, including the inheritance/`BUILTIN\Users` cleanup described below

## Challenges & Troubleshooting

Real problems hit during the build, and how each was diagnosed and fixed:

**1. "Windows cannot find the Microsoft Software License Terms" during Server 2022 install**
*Cause:* VMware's "Easy Install" feature had attached an auto-generated floppy disk (`autoinst.flp`) that was malformed for the multi-edition evaluation ISO.
*Fix:* Removed the floppy device from VM settings and completed Windows Setup manually.

**2. Server installed as Core when GUI was expected**
*Cause:* The edition-selection step during Easy Install's interrupted flow defaulted to a Core edition.
*Fix:* Evaluated the trade-off deliberately rather than reinstalling — kept Server Core for both DC01 and FS01, since it's smaller, more production-realistic, and pushed the whole project toward PowerShell/RSAT-based remote management rather than local GUI administration.

**3. Domain join failed — "AD DC for corp.local could not be contacted"**
*Cause:* The VM's network adapter defaulted to the generic Hyper-V/VMware host-only network rather than the specific custom isolated network built for the lab, resulting in a DHCP-assigned address on the wrong subnet.
*Fix:* Diagnosed via `ipconfig /all` showing an unexpected subnet, then explicitly reassigned the adapter to the correct custom virtual network in VM settings.

**4. SConfig static IP configuration silently cancelled**
*Cause:* Leaving the default gateway prompt blank (correct for an isolated network with no router) cancelled the entire operation instead of just skipping that field, on this Server Core build.
*Fix:* Bypassed the interactive menu and set the static IP directly via `New-NetIPAddress` / `Set-DnsClientServerAddress` in PowerShell.

**5. File share access denied despite correct NTFS permissions**
*Cause:* NTFS and SMB share permissions are two independent layers — the share itself had only been granted to Domain Admins, so a Finance user with correct NTFS rights was still blocked at the network-share layer. Windows applies the more restrictive of the two.
*Fix:* Granted each department's security group matching access at the share level with `Grant-SmbShareAccess`, so both layers agree.

**6. Inherited `BUILTIN\Users` permission left every domain user with access to a "restricted" share**
*Cause:* New subfolders inherit their parent folder's permissions by default; `C:\Shares` had inherited a broad `Users` entry that flowed down into each department folder.
*Fix:* Verified via `Get-Acl`, then disabled inheritance and stripped the inherited entry with `icacls` (PowerShell's native ACL cmdlets didn't fully clear this particular inherited entry).

**7. RSAT installation failed with Windows Update error `0x8024402c`**
*Cause:* RSAT features download on-demand from Windows Update, but CLIENT01 had no internet access by design (isolated network).
*Fix:* Temporarily added a second NAT-mode network adapter for internet access during the RSAT install, then removed it afterward to restore full network isolation.

## Skills Demonstrated

- Active Directory design: OU structure, security group strategy, forest/domain promotion
- Group Policy: password policy, preference-based drive mapping with item-level targeting, administrative template restrictions, and OU-based policy inheritance/exception design
- Windows Server Core administration and remote management via RSAT
- PowerShell scripting and automation (bulk provisioning, ACL remediation)
- NTFS and SMB share permission design (defense-in-depth, least privilege)
- Systematic troubleshooting across networking, permissions, and OS configuration layers

## Future Enhancements Considered

Scoped out for this phase to keep focus tight, but worth noting as a sign of what's next:
- Delegated Help Desk permissions (least-privilege delegation instead of Domain Admin for routine tasks)
- An offboarding script to complement the provisioning script (full account lifecycle)
- A Fine-Grained Password Policy for privileged/IT accounts
- Shadow Copies on the file server for self-service file recovery

## Next Steps

This on-prem environment becomes the foundation for the next phase: extending identity into the cloud with M365, Entra ID, and Intune, then connecting the two environments with an Azure site-to-site VPN.

## Screenshots

*(Add your own screenshots here — suggested set: OU structure in ADUC, security group membership, the bulk provisioning script running, a restricted user being denied access to the wrong share, the drive-map GPO in effect, Control Panel blocked for a Staff user but not IT, and the `icacls` output confirming the permission fix.)*
