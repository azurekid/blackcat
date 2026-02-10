# BlackCat v1.0.0 Release Summary

## 📋 Overview

BlackCat v1.0.0 introduces the new AzureHacking Security Blog experience and polishes core module behavior. This release focuses on documentation, researcher workflows, and a small but important reliability fix in `Set-FederatedIdentity`, plus manifest cleanup for deprecated functions.

## 📝 Release Summary

**What's New at a Glance:**
* New static security blog under `website/blog` with search, tagging, and sharing
* Admin editor for drafting and managing posts with Azure Static Web Apps auth
* New research posts covering diagnostic setting abuse, Key Vault, Entra ID, and BlackCat onboarding
* `Set-FederatedIdentity` now consistently uses `Get-ManagedIdentity -OutputFormat Object`
* Manifest cleanup: removed deprecated Entra role assignment helpers from exports

**Key Benefits:**
* Easier distribution of Azure and Entra ID security research alongside the module
* Streamlined content authoring with a local-first admin experience and optional API-backed publishing
* More reliable behavior from `Set-FederatedIdentity` in pipelines and scripted workflows
* Cleaner public surface area that reflects currently supported functions

## 🔍 New AzureHacking Security Blog

The new static blog (located in `website/blog`) provides a lightweight, Azure-friendly way to publish security research:

* **Static-first architecture** — Pure HTML/CSS/JS site suitable for Azure Static Web Apps or Blob static hosting
* **Search & tagging** — Client-side full-text search with tag filtering and recent-post sidebar
* **Markdown-based posts** — Posts stored as `.md` files under `website/blog/posts` with `posts/index.json` metadata
* **Admin editor** — `admin.html` offers live Markdown preview, local drafts in `localStorage`, and optional publishing via `/api` endpoints
* **SWA integration** — `staticwebapp.config.json` wires `/admin.html` and API routes to Entra ID-backed authentication

## 📚 New & Updated Content

This release adds several long-form research and getting-started posts:

* **Diagnostic settings deep dive** — "Impairing Azure Defenses Through Diagnostic Setting Manipulation" expands on the `Disable-DiagnosticSetting` function and T1562.008 techniques
* **Key Vault hardening** — "Azure Key Vault Security: A Red Team Perspective" covers common misconfigurations and extraction paths
* **Privilege escalation in Entra ID** — "Detecting Privilege Escalation in Entra ID" documents role-based escalation vectors and detection approaches
* **BlackCat onboarding** — "Getting Started with the BlackCat PowerShell Module" guides new users through installation, auth, and first assessments

The blog also ships with an updated `sitemap.xml` for search engines and a curated `posts/index.json` with metadata including tags, images, and estimated read time.

## 🛠️ Module Changes

### `Set-FederatedIdentity` Reliability Fix

`Set-FederatedIdentity` now explicitly calls:

```powershell
Get-ManagedIdentity -Name $ManagedIdentityName -OutputFormat Object
```

This guarantees a stable object-based contract regardless of global or caller-specific output format preferences, reducing the chance of unexpected behavior in pipelines or automated scripts.

### Manifest Cleanup

The module manifest (`BlackCat.psd1`) has been updated to remove the following deprecated functions from `FunctionsToExport` and `FileList`:

* `Get-EntraRoleAssignment`
* `Get-EntraRoleAssignmentMap`

This ensures the exported function list matches the supported public API and prevents confusion when browsing available commands.

## Testing Notes

* Existing core discovery and persistence functions remain unchanged in this release
* The `Set-FederatedIdentity` change is backward compatible but more robust when composing with `Get-ManagedIdentity`
* Website/blog assets are fully static and can be validated locally by opening `website/blog/index.html` in a browser, or deployed to Azure Static Web Apps / static website hosting for end-to-end testing

---

For a chronological view of all module changes, see the main [CHANGELOG.md](CHANGELOG.md).
