# Phase 2: Hybrid Identity — Microsoft 365, Entra ID & Intune

**Part of the larger Enterprise Hybrid Identity & Infrastructure portfolio project.** This phase extends the [on-prem AD/GPO/File Server foundation](../01-onprem-ad-gpo-fileserver/) into the cloud, turning a self-contained on-prem environment into a genuinely hybrid one — the same identities now work both on-prem and in Microsoft 365/Intune-managed contexts.

## Overview

An on-prem-only directory doesn't reflect how most modern organizations actually operate — employees need the same identity to work across on-prem file shares, cloud email, Teams, and company-managed devices. This phase builds that bridge: a Microsoft 365 tenant, a sync engine connecting it to the existing `corp.local` forest, cloud-side access control (Conditional Access), and basic device management (Intune) — the identity and device-management layer a help desk role actually lives in day-to-day.

## Architecture

```
   On-prem (VMnet2, isolated)                          Cloud (Microsoft 365 tenant)
   192.168.10.0/24                                      umair.onmicrosoft.com

┌─────────────────┐                                  ┌───────────────────────┐
│   DC01 (.10)     │                                  │      Entra ID          │
│  AD DS + DNS     │                                  │  (users, groups synced │
│  corp.local      │                                  │   from corp.local)     │
└────────┬─────────┘                                  └──────────┬────────────┘
         │                                                        │
         │ read AD (HQ OU only)                    Conditional Access
         │                                          (require MFA, all users,
┌────────▼─────────┐        Password Hash            break-glass excluded)
│    SYNC01 (.40)   │        Sync + user/group                    │
│ Entra Connect Sync│ ──────────────────────────────►             │
│ Dual-homed:        │        (one-way, on-prem → cloud)  ┌────────▼────────┐
│  VMnet2 + NAT      │                                     │     Intune       │
└───────────────────┘                                     │ (device mgmt +   │
                                                            │  compliance)     │
┌──────────────────┐                                       └────────┬─────────┘
│  CLIENT01 (.30)   │◄──────────────────────────────────────────────┘
│ Domain-joined +   │        Microsoft Entra registered, enrolled,
│ Entra registered  │        BitLocker-compliant
└───────────────────┘
```

## Environment & Tools

| Component | Role | Notes |
|---|---|---|
| SYNC01 | Entra Connect Sync server | Windows Server 2022, **Desktop Experience** (the one VM in the lab needing a GUI — Entra Connect's installer requires it) |
| Microsoft 365 tenant | Cloud identity + device management | `umair.onmicrosoft.com`, Business Premium trial |
| CLIENT01 | Test device | Reused from Phase 1 — domain-joined, now also Entra-registered and Intune-enrolled |

**Networking note:** SYNC01 is dual-homed — a static IP on the isolated `VMnet2` (to read on-prem AD) plus a NAT adapter (to reach Microsoft's cloud endpoints continuously). Every other VM in the lab is deliberately internet-isolated; this is the one necessary exception.

## What Was Built

- **Microsoft 365 Business Premium trial tenant** (pivoted from the Developer Program sandbox — see [Challenges](#challenges--troubleshooting))
- **Microsoft Entra Connect** on SYNC01, configured with:
  - Password Hash Synchronization
  - Custom Domain/OU filtering — scoped to the `HQ` OU only, deliberately excluding default AD containers and built-in accounts
  - UPN fallback to the tenant's default domain, since `corp.local` isn't a routable/verifiable domain
- **Initial sync verified**: all 7 on-prem users now appear in Entra ID
- **Active Directory Recycle Bin enabled** on `corp.local` (flagged as a best-practice gap by Entra Connect itself)
- **Break-glass Global Administrator account**, excluded from all Conditional Access policies
- **Conditional Access policy** (`CA01 - Require MFA for all users`), rolled out safely via Report-only mode before enforcing
- **Intune device enrollment** for CLIENT01 (Microsoft Entra registered + MDM-managed)
- **Intune compliance policy** (BitLocker required, minimum 8-character password, 90-day expiration) — demonstrated a real non-compliant → compliant transition by enabling BitLocker

## Design Decisions

- **Business Premium trial over the Developer Program sandbox.** Not the original plan, but arguably the better outcome — Business Premium includes Entra ID P1 and Intune outright, both of which this phase actually needed.
- **SYNC01 kept as a separate, dedicated server rather than installing Entra Connect on DC01.** Real best practice — sync tooling shouldn't run directly on a domain controller.
- **Sync scoped to a single OU, not the whole directory.** Mirrors the same deliberate-scoping philosophy from Phase 1's security groups — only real organizational objects go to the cloud, not built-in AD containers.
- **Password Hash Sync over Pass-through Authentication or Federation.** Simplest hybrid sign-in method, no additional on-prem infrastructure required — the right choice for this scale.
- **Conditional Access rolled out via Report-only mode first, with a break-glass account excluded from the start.** Both are genuine production practices, not just lab conveniences — skipping either is one of the most common ways real organizations lock themselves out of their own tenant.
- **Microsoft Entra registration rather than full Hybrid Azure AD Join.** A deliberate scope decision — registration is enough to prove real Intune management, while full hybrid join needs additional Entra Connect device-sync configuration that wasn't necessary to demonstrate the core concept.

## Challenges & Troubleshooting

**1. Microsoft 365 Developer Program sandbox — access denied**
*Cause:* Microsoft has tightened free sandbox eligibility; it's no longer automatically granted on signup.
*Fix:* Pivoted to a standard, self-serve Microsoft 365 Business Premium trial instead — a different eligibility system entirely, and one that happened to include better licensing (Entra ID P1, Intune) for this phase anyway.

**2. `corp.local` UPN suffix not routable for cloud sign-in**
*Cause:* `.local` isn't a valid public domain suffix, so Entra Connect couldn't map on-prem UPNs directly to a verified cloud domain.
*Fix:* Used Entra Connect's "continue without matching all UPN suffixes" option, letting synced users sign in via the tenant's default domain instead. Documented as a known trade-off of a lab without a purchased public domain.

**3. Conditional Access policy had no visible effect**
*Cause:* The policy was still in Report-only mode — it evaluates but never enforces.
*Fix:* Confirmed via the sign-in log's Report-only tab, then switched the policy to On.

**4. Conditional Access policy still wouldn't enable**
*Cause:* The tenant's Security Defaults were still active — Security Defaults and custom Conditional Access policies are mutually exclusive.
*Fix:* Disabled Security Defaults, then the custom policy activated correctly. Retested and confirmed a synced user was correctly challenged for MFA.

**5. Intune enrollment failed at the Terms of Use step (error -895156188)**
*Cause:* Synced on-prem users had no Microsoft 365 license assigned — device management entitlement comes from licensing, not just tenant membership.
*Fix:* Assigned Business Premium licenses to the affected users.

**6. Device registration blocked — "You don't have the right privileges"**
*Cause:* The tenant-level setting "Users may register their devices with Microsoft Entra ID" was restricted rather than open to all users.
*Fix:* Set it to **All** under Entra ID device settings.

**7. Same privilege error persisted specifically during MDM enrollment**
*Cause:* A different requirement from #6 — enrolling an already-registered device into Intune specifically requires the signed-in Windows user to hold **local administrator rights** on that machine, which a standard domain user doesn't have by default.
*Fix:* Completed the enrollment step from the `CORP\Administrator` session instead. Noted Windows Autopilot as the real-world solution to this exact friction point (it enrolls devices before a standard user ever logs in).

**8. Couldn't troubleshoot via Windows Settings on the test user's account**
*Cause:* Not a new bug — this was Phase 1's own Control Panel/Settings restriction GPO, correctly applying to a Staff-OU user exactly as designed.
*Fix:* Used Company Portal (unaffected by that GPO) instead, or performed the step from an IT-OU/Administrator session. A good example of policies from one phase of a project genuinely interacting with work in a later phase.

**9. `dsregcmd /status` showed an AD Configuration Test failure**
*Cause:* Investigated and correctly identified as Windows' own automatic background hybrid-join attempt (triggered simply because the machine is domain-joined) — unrelated to the actual Microsoft Entra registration path being used. A useful reminder not to chase every diagnostic red flag without confirming it's actually relevant to the problem at hand.

**10. CLIENT01 showed Non-compliant after the compliance policy was assigned**
*Cause:* No BitLocker enabled on the VM's virtual disk — the policy correctly detected a genuine gap rather than malfunctioning.
*Fix:* Enabled a virtual TPM and turned on BitLocker; device transitioned to Compliant on re-evaluation.

## Skills Demonstrated

- Hybrid identity architecture and Entra Connect configuration (sync scoping, sign-in method selection, non-routable domain handling)
- Cloud identity administration: licensing, device registration settings, tenant-level configuration
- Conditional Access policy design following safe rollout practice (break-glass account, Report-only before enforcement)
- Intune device enrollment and compliance policy management
- Cross-system troubleshooting spanning on-prem AD, Entra ID, and Intune — including correctly identifying an unrelated diagnostic signal rather than chasing it

## Future Enhancements Considered

- Full Hybrid Azure AD Join (this phase used Microsoft Entra registration only)
- Password writeback (requires premium licensing beyond what's assigned here)
- Windows Autopilot for zero-touch enrollment, avoiding the local-admin requirement hit during manual enrollment
- A custom verified domain, to resolve the UPN suffix limitation properly

## Next Steps

The final phase of this project connects the on-prem *network* itself to Azure via a Site-to-Site VPN — distinct from this phase's identity-layer connection, and the piece that completes the full hybrid infrastructure story.

## Screenshots

*(Suggested set: Entra Connect configuration summary, the synced user list in Entra ID, the sign-in log showing an MFA challenge, the Intune device list showing CLIENT01 enrolled and compliant, and the BitLocker-driven non-compliant → compliant transition.)*
