# Enterprise Hybrid Identity & Infrastructure

A portfolio project demonstrating help desk, cloud, and networking skills through a progressively built hybrid IT environment — starting on-prem, extending into the cloud, and eventually connecting both via Azure networking.

## Project Phases

- **[Phase 1: On-Prem AD, GPO & File Server](./01-onprem-ad-gpo-fileserver/)** — Active Directory, Group Policy, file services, and PowerShell-based bulk user provisioning on Windows Server 2022.
- **[Phase 2: Hybrid Identity — M365, Entra ID & Intune](./02-hybrid-identity-m365/)** — Extends the on-prem directory into the cloud via Microsoft Entra Connect, adds Conditional Access and Intune device management.
- **Phase 3: Azure VNet + Site-to-Site VPN** *(planned)* — Connects the on-prem network itself to Azure, completing the hybrid infrastructure story.

Each phase folder contains its own detailed README covering architecture, design decisions, and real troubleshooting encountered during the build.

## Skills Demonstrated Across This Project

- Active Directory design, Group Policy, and file server administration
- PowerShell scripting and automation (bulk provisioning, ACL remediation)
- Hybrid identity architecture (Entra Connect, Conditional Access, Intune)
- Systematic troubleshooting across on-prem, cloud, and cross-system boundaries

## About

Built as part of a certification and portfolio track targeting IT help desk, MSP, and junior network engineer roles.
