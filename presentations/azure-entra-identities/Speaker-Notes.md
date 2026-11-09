# Borrowed Trust: Stealing Azure & Entra Identities

**Presenter:** Rogier Dijkman / AzureHacking
**Format:** 16:9 editable PowerPoint and self-contained browser deck
**Audience:** Cloud engineers, Entra administrators, security operations, authorized testers
**Timing:** 35-minute narrative + 5-minute offline demo + 5-minute Q&A
**Research date:** 2026-11-09
**Scope:** One documented Microsoft incident, one explicitly labeled training storyline,
seven practical identity-abuse examples, defensive hunting queries, and all 61
public repositories (20 forks and 41 non-forks).

## How to present

Open `Azure-Entra-Identity-Abuse.pptx` in PowerPoint; use Presenter View for embedded notes.
Alternatively open `Azure-Entra-Identity-Abuse.html` locally. Arrow keys or Page Up/Down
navigate, N toggles notes, and the Fullscreen button enters presentation mode. Browser
printing includes every slide, not only the currently visible slide.
Open `Offline-Demo.html` separately for the five-minute synthetic trust-path demonstration.
No cloud credentials, deployment, external scripts, or network access are required.

## Evidence and limitations

The real incident is Midnight Blizzard's attack on Microsoft, as documented in Microsoft's
January and March 2024 disclosures. Blue Mountain Travel is a training application and
mc2-connect a tabletop, not a verified customer breach or an invented personal engagement.

Every public azurekid repository returned by GitHub was inventoried. Repository descriptions,
README summaries, and relevant directory listings were reviewed; this is not a full audit of
every codebase. Forks are identified and not attributed as original work. The empty mc2connect
repository and sparsely documented projects are labeled conservatively.

AzureHacking is an explicit reference throughout the deck. Direct access to the website,
its www hostname, and its public Blob hostname failed DNS resolution in this environment.
The site's source `llms.txt` and `sitemap.xml` supplied article descriptions and current
canonical paths. An archived published copy of the diagnostic-setting article was read.
Full text of every other article was not independently retrieved; their catalogue claims
were cross-checked against relevant project documentation and Microsoft platform constraints.
No unpublished article text, review tokens, secrets, or private infrastructure details are
included. Article descriptions were synthesized, not copied as a substitute for the originals.
Live availability of those website links remains unverified; recheck before delivery.

The two KQL examples use documented Microsoft Sentinel schemas. They are broad hunting
examples, not production-ready analytics; no real tenant/workspace was available for execution.
Tune log ingestion, field values, expected activity, retention, and false positives locally.
Source demonstrations were qualified where they could otherwise imply automatic anonymous
deleted-blob access, wildcard standard FIC subjects, Contributor-to-Owner role creation,
automatic PIM activation, unrestricted privileged-group control, or universal token/MFA bypass.

## Slide-by-slide script

### 01. Borrowed Trust: Stealing Azure & Entra Identities

**AZUREHACKING / ROGIER DIJKMAN | 00:00-01:00**

- **The premise:** You do not need an administrator's password if you can become an identity they already trust.
- **The journey:** One real incident. A training-story attack chain. Seven practical identity-abuse patterns.
- **The boundary:** Authorized assessment and defense only. No production exploitation or real credentials.

**Land this line:** The perimeter is a graph of trust.

Open with the title, then pause before the premise. This is a presentation about how identity
misconfigurations compose, not about exploiting a mysterious Azure vulnerability.
The intended audience is cloud engineers, identity administrators, security operations analysts,
and authorized security testers. The default slot is 45 minutes: 35 minutes of narrative,
five minutes of an offline demonstration, and five minutes of questions.
BlackCat here means Rogier's Azure assessment project, not the similarly named ransomware group.

**Sources:** [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat); [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra); [AzureHacking research website](https://azurehacking.com)

### 02. "We deleted the file."

**COLD OPEN / TRAINING STORY | 01:00-02:00**

- **The reassurance:** An onboarding document was removed after someone noticed a public link.
- **The unanswered question:** Was a usable credential copied before deletion, or retained in another accessible copy?
- **The consequence:** That credential may still authenticate an application that can influence a stronger identity.

**Land this line:** Deleting an artifact is not revoking its authority.

Tell this as a hypothetical training story: a team fixes the visible mistake and assumes the
incident is over. Ask the audience: 'Which identity did that file represent?'
Do not claim this happened to a named customer or to you personally. Blue Mountain Travel is an
intentionally vulnerable training application, and mc2-connect is explicitly a tabletop exercise.
Its story will carry the talk, while Microsoft's public incident supplies the real-world evidence.
Avoid the blanket assertion that anonymous callers can recover all soft-deleted blobs.
Copying before removal is sufficient for this opening and does not depend on that assertion.

**Sources:** [Blue Mountain Travel tenant-takeover tabletop](https://github.com/azurekid/mc2-connect); [Blue Mountain Travel: intentionally vulnerable training app](https://github.com/azurekid/bluemountaintravel); [AzureHacking: Azure Tenant Takeover](https://azurehacking.com/post/azure-tenant-takeover-from-exposed-config-to-global-admin)

### 03. Four identities. Three permission planes.

**FOUNDATIONS | 02:00-04:00**

- **Human account:** Interactive sign-in, multifactor authentication (MFA), groups, and eligible or active roles.
- **Application / service principal:** App registration is the application definition; its tenant-local service principal holds access.
- **Managed / federated workload:** Azure-managed identity, or external workload trust, can obtain resource-specific access tokens.

**Land this line:** Entra directory roles != Azure RBAC != Microsoft Graph permissions.

Define Microsoft Entra ID as the identity service, Azure role-based access control (RBAC)
as authorization over Azure resources, and Microsoft Graph as an API with its own permissions.
A managed identity is represented by a service principal; federation is an authentication
method, not a fourth permission system. A multi-tenant application can have a different
service principal in each tenant. Application/client ID and service-principal object ID are
not interchangeable. A subscription Contributor is not automatically an Entra administrator.
Use this distinction repeatedly whenever the story crosses a permission boundary.

**Sources:** [Microsoft: managed identity security boundary](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq); [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference); [Microsoft: Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)

### 04. Acquire -> authenticate -> authorize -> act

**MENTAL MODEL | 04:00-05:00**

- **Acquire:** A password, application credential, bearer token, workload execution path, or trusted workflow.
- **Authenticate:** A token is issued for a particular audience; a Graph token is not automatically an ARM token.
- **Authorize:** The resource checks permissions and scope. Authentication success does not guarantee access.

**Land this line:** A signed token can be valid while its use is malicious.

Expand Azure Resource Manager (ARM), OAuth 2.0, and OpenID Connect (OIDC).
A bearer access token can be usable by its holder until expiry or applicable revocation enforcement;
do not imply that all tokens can be replayed, renewed indefinitely, or used at every API.
Distinguish theft of an existing token from obtaining a fresh token through control of a runtime,
credential, or federated trust. The latter may create recurring access, whereas a copied access
token alone typically does not. Token acquisition and subsequent API activity are separate events.
MITRE Cloud Accounts T1078.004 is a useful umbrella; exact technique mapping depends on the path.

**Sources:** [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference); [MITRE: Cloud Accounts (T1078.004)](https://attack.mitre.org/techniques/T1078/004/)

### 05. Midnight Blizzard: the test-tenant foothold

**DOCUMENTED INCIDENT / MICROSOFT | 05:00-07:00**

- **Late November 2023:** Password spraying compromised a legacy, non-production test account without MFA.
- **12 January 2024:** Microsoft detected the attack; its 19 January disclosure described corporate email theft.
- **8 March 2024 update:** Microsoft reported access to some source-code repositories and internal systems using stolen information.

**Land this line:** A non-production label did not contain the trust relationship.

This is the real incident, not a reconstruction of the Blue Mountain lab.
Attribute the timeline explicitly to Microsoft. The January disclosure said the attack was not
the result of a vulnerability in Microsoft products or services. It also described a very small
percentage of corporate email accounts, including senior leadership and security/legal functions.
Do not repeat January's 'no source-code access' statement as if it were the final finding:
the March update changed the known scope. The March update said Microsoft had found no evidence,
as of that update, that Microsoft-hosted customer-facing systems were compromised.
Avoid inventing specific production privileges, tenant architecture, or details not disclosed.

**Sources:** [Microsoft incident disclosure, 19 January 2024](https://www.microsoft.com/en-us/msrc/blog/2024/01/microsoft-actions-following-attack-by-nation-state-actor-midnight-blizzard); [Microsoft responder guidance, 25 January 2024](https://www.microsoft.com/en-us/security/blog/2024/01/25/midnight-blizzard-guidance-for-responders-on-nation-state-attack/); [Microsoft incident update, 8 March 2024](https://www.microsoft.com/en-us/msrc/blog/2024/03/update-on-microsoft-actions-following-attack-by-nation-state-actor-midnight-blizzard)

### 06. From a user foothold to application access

**DOCUMENTED INCIDENT / IDENTITY CHAIN | 07:00-09:00**

- **Initial foothold:** The compromised account led to a legacy test OAuth application with elevated corporate access.
- **Identity transition:** Microsoft described additional malicious OAuth applications and consent activity.
- **Impact:** Exchange Online application access enabled targeted corporate email collection via Exchange Web Services.

**Land this line:** The attacker changed identity, not just location.

Use a simple verbal chain: account -> trusted legacy application -> additional application
access -> email collection. Microsoft's 25 January guidance reports that the actor created
a new user account to grant consent to additional malicious OAuth applications and used the
legacy test application to grant the Exchange Online full_access_as_app role.
This is an Exchange application role, not a Microsoft Graph permission. Do not describe this
as a managed-identity attack; that is a separate class of example later in the presentation.
The key defensive lesson is that app-based access can outlive containment of the first human
account. Keep this at an explanatory level, without giving a replication procedure.

**Sources:** [Microsoft responder guidance, 25 January 2024](https://www.microsoft.com/en-us/security/blog/2024/01/25/midnight-blizzard-guidance-for-responders-on-nation-state-attack/)

### 07. What 'just a test account' really means

**DOCUMENTED INCIDENT / LESSONS | 09:00-10:00**

- **Trust follows permissions:** Test identities and old apps can still reach production data.
- **MFA is necessary, not sufficient:** Human-account controls do not remove existing application grants or app credentials.
- **Contain the whole chain:** Review users, apps, consent, credentials, and the information accessed.

**Land this line:** Inventory dormant trust, not only active administrators.

Separate the disclosed facts from recommendations. The recommendations here are ours, derived
from the incident, not additional claims about Microsoft's environment.
SprayCat is relevant as an authorized way to validate the human-account attack surface,
not as a claim that it was used in this incident. VizCa provides a complementary policy
coverage view. Neither tool should be described as guaranteeing complete security.
Ask the audience to name an abandoned tenant, test application, or automation account
that still has production access. That makes the incident immediately relatable.

**Sources:** [Microsoft responder guidance, 25 January 2024](https://www.microsoft.com/en-us/security/blog/2024/01/25/midnight-blizzard-guidance-for-responders-on-nation-state-attack/); [SprayCat: authorized password-spray assessment](https://github.com/azurekid/spraycat); [VizCa: Conditional Access coverage](https://github.com/azurekid/VizCa)

### 08. Blue Mountain Travel: the Friday shortcut

**AZUREHACKING / CLEARLY LABELED TABLETOP | 10:00-11:00**

- **Business context:** HR onboarding, shared documents, deployment automation, and an Azure managed identity.
- **Small decisions:** An exposed document, a stored app secret, excessive identity rights, and editable workload trust.
- **Assessment question:** Can the least-protected component influence the highest-privileged identity?

**Land this line:** This is your training scenario, not an asserted customer breach.

Ground the story in mc2-connect and the AzureHacking tenant-takeover article catalogue.
The associated bluemountaintravel README explicitly identifies an intentionally vulnerable
training application, including exposed SAS tokens, hardcoded credentials, and weak access controls.
Do not deploy it with real data or treat it as a production-ready reference architecture.
Our presentation is a technically qualified adaptation, not a literal endorsement of every
shortcut in the repository's attack-flow diagram. Its dates, characters, and company are lab
devices rather than independent evidence of a real compromise.

**Sources:** [Blue Mountain Travel tenant-takeover tabletop](https://github.com/azurekid/mc2-connect); [Blue Mountain Travel: intentionally vulnerable training app](https://github.com/azurekid/bluemountaintravel); [AzureHacking: Azure Tenant Takeover](https://azurehacking.com/post/azure-tenant-takeover-from-exposed-config-to-global-admin)

### 09. A chain only works when every gate opens

**TABLETOP / ATTACK-PATH GATES | 11:00-13:00**

- **Storage -> application:** Readable material contains a still-valid secret; the app has useful effective permissions.
- **Application -> managed identity:** The foothold can change the relevant trust or execute on an identity-enabled resource.
- **Managed identity -> directory control:** Already-granted Graph capabilities permit further grants or directory role management.

**Land this line:** Every arrow needs a permission, an object, and a scope.

Show the audience the difference between an attractive attack diagram and a verified path.
For each arrow ask: what principal performs the action, which API checks authorization,
which object is in scope, and what prerequisite is missing?
In the lab story a leaked application credential is not intrinsically administrative.
Editing a user-assigned managed identity's federated credentials requires the relevant
Azure management permissions. A subscription role does not itself grant Graph privileges.
Directory control additionally requires dangerous, effective Graph permissions on that identity.
Treat failed or blocked arrows as successful defenses, not as reasons to improvise an attack.

**Sources:** [Blue Mountain Travel tenant-takeover tabletop](https://github.com/azurekid/mc2-connect); [Microsoft: managed identity security boundary](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq); [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference); [AzureHacking: Federated Identity Credential Injection](https://azurehacking.com/post/federated-identity-credential-injection-proof-of-concept)

### 10. The config backup that still authenticates

**PRACTICAL EXAMPLE 1 / LEAKED APP IDENTITY | 13:00-14:00**

- **Misconfiguration:** An application secret is stored in a readable share, build artifact, or abandoned backup.
- **Identity abuse:** A holder can authenticate as the app; impact is bounded by that service principal's effective access.
- **Break the path:** Revoke exposed credentials, restrict storage, reduce app permissions, and review sign-in evidence.

**Land this line:** A client ID identifies an app. A client secret authenticates it.

A Shared Access Signature (SAS) is a scoped storage capability, not automatically an Entra
identity. It can nonetheless expose the material needed to obtain one.
Explain that removing the file or rotating a storage credential does not automatically
revoke a different application secret copied from that file. Review each credential separately.
If relying on retained versions, distinguish live versions from soft-deleted data and test
the actual caller's authorized access. Deletion/versioning is not a universal anonymous-read
bypass, and disabling retention is not the recommended fix. Preserve recovery protections
while correcting exposure and credential lifetime.
BlackCat is the authorized assessment bridge; no secrets or real tenant IDs appear in the deck.

**Sources:** [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat); [Blue Mountain Travel: intentionally vulnerable training app](https://github.com/azurekid/bluemountaintravel); [Microsoft: managing soft-deleted blobs](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-manage); [AzureHacking: Azure Tenant Takeover](https://azurehacking.com/post/azure-tenant-takeover-from-exposed-config-to-global-admin)

### 11. The workload is the identity boundary

**PRACTICAL EXAMPLE 2 / MANAGED IDENTITY | 14:00-15:00**

- **Misconfiguration:** A VM, Function, or automation runtime uses an identity with more rights than its workload needs.
- **Identity abuse:** Control of eligible code execution can obtain that workload's tokens; no stored password is required.
- **Break the path:** Protect execution and deployment rights; isolate identities; scope permissions to actual operations.

**Land this line:** Secretless does not mean unstealable or un-abusable.

Microsoft's managed identity FAQ states that the security boundary is the attached resource.
For a VM, code running on the VM can request its managed-identity tokens.
Do not generalize a VM's metadata endpoint to every Azure service; runtime endpoints and
access conditions vary. An SSRF issue only reaches this path if it can access the relevant
endpoint with the required request properties. No endpoint request or token extraction
command is needed for this presentation.
Granting deployment or code-execution control over a resource can effectively confer access
to its attached identity. Using that identity against Graph still requires Graph permissions.
Evaluate reusable user-assigned identities for cross-workload blast radius.

**Sources:** [Microsoft: managed identity security boundary](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq); [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat)

### 12. No client secret. Still a trust problem.

**PRACTICAL EXAMPLE 3 / FEDERATED TRUST | 15:00-17:00**

- **Misconfiguration:** A powerful identity trusts a weakly protected workflow or allows unauthorized trust changes.
- **Identity abuse:** An accepted external assertion can be exchanged for an Azure/Entra access token.
- **Break the path:** Protect workflows and environments; pin actions; restrict trust writers and identity privileges.

**Land this line:** Federation moves the secret-management problem to trust management.

Define federated identity credential (FIC). Microsoft checks issuer, subject, and audience.
For standard FICs these values must match case-sensitively; do not assume a literal star
in a normal subject creates wildcard trust. Expression-based flexible federation, where
supported, is a distinct feature and must be assessed under its documented rules.
This qualifies the policy-as-code README's wildcard illustration rather than copying it.
An exact production-environment subject also depends on GitHub environment protection and
workflow integrity: an exact string is not a substitute for authorization in GitHub.
In a trust-injection scenario the ability to edit the FIC is the prerequisite, not mere knowledge
of a client ID. Present AzureHacking's federation research as research, not an observed breach.

**Sources:** [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure); [Policy-as-Code identity demonstration](https://github.com/azurekid/policy-as-code); [AzureHacking: Federated Identity Credential Injection](https://azurehacking.com/post/federated-identity-credential-injection-proof-of-concept)

### 13. The onboarding permission with a second job

**PRACTICAL EXAMPLE 4 / GRAPH PERMISSIONS | 17:00-19:00**

- **Business justification:** 'The automation needs to assign employees to enterprise applications.'
- **Risk:** AppRoleAssignment.ReadWrite.All can manage app-role grants, including powerful application permissions.
- **Escalation gate:** Directory role assignment needs a capability such as RoleManagement.ReadWrite.Directory.

**Land this line:** Review what a permission can do, not what its name suggests.

This is the central permission-creep lesson in mc2-connect. App-role assignments and Entra
directory-role assignments are different objects and authorization operations.
Do not say AppRoleAssignment.ReadWrite.All directly assigns Global Administrator.
The example is conditional: an identity already holding the dangerous app-role grant capability
may be able to grant additional Graph application privileges, after which directory-role
management becomes possible. Consent/grant requirements and current platform restrictions
must be verified for the exact objects; permission names alone are not proof.
A newly added grant can require a fresh token before new roles appear in token claims.
Use a graph screenshot or synthetic relationship map, not a live role-writing command.

**Sources:** [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference); [Blue Mountain Travel tenant-takeover tabletop](https://github.com/azurekid/mc2-connect); [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra); [AzureHacking: Detecting Privilege Escalation in Entra ID](https://azurehacking.com/post/detecting-privilege-escalation-in-entra-id)

### 14. Contributor is not Global Administrator

**PERMISSION PLANES / COMMON MISREAD | 19:00-20:00**

- **Azure resource control:** Contributor can manage many resources but cannot directly create RBAC role assignments.
- **Data-plane access:** Key Vault resource management is not automatically permission to read secrets under Azure RBAC.
- **Indirect identity control:** Changing app credentials or privileged workload code can expose another principal's access.

**Land this line:** Direct privileges and reachable privileges are different.

This is the technical reality check that makes the talk credible.
Do not claim Contributor can deploy an Owner assignment through a template merely because
it can deploy resources: the target operation still checks role-assignment authorization.
Key Vault's access-policy model and RBAC model have different risk profiles. In the legacy
access-policy model, control over access policies can be a path to data access; under RBAC,
vault-management permissions alone are not the secret-reading role.
Microsoft explicitly warns that Application Administrator can manage application credentials
and impersonate an app's identity. It cannot consent to Microsoft Graph application permissions
simply by holding that role. Review existing app privileges separately from new consent.

**Sources:** [Microsoft: Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles); [Microsoft: Key Vault RBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide); [Microsoft: Application Administrator permissions](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#application-administrator); [AzureHacking: Azure Key Vault Security Deep Dive](https://azurehacking.com/post/azure-key-vault-security-deep-dive)

### 15. Eligible is not harmless. Eligible is not active.

**PRACTICAL EXAMPLE 5 / PIM | 20:00-21:00**

- **Misconfiguration:** Weak activation controls, stale eligibility, or overlooked authority over privileged groups/apps.
- **Identity abuse:** A compromised principal may reach stronger rights if activation and membership gates permit it.
- **Break the path:** Require appropriate authentication, approval and duration; review eligibility and control relationships.

**Land this line:** Map the path to privilege, not only today's active roles.

Expand Privileged Identity Management (PIM). Eligibility is conditional authority, not an
automatic active assignment. Show MFA, authentication context, approval, activation time,
and duration as real gates. A graph risk edge is not proof that every gate is bypassable.
Role-assignable groups have stronger restrictions; ordinary group management does not
automatically let a Groups Administrator alter a role-assignable group.
Do not conflate nested groups, Azure RBAC group access, and Entra role-assignable group rules.
ScEntra is useful for relationship analysis; PIM, PaC, and Piceb support governance automation.
Any governance deployment identity is itself privileged and must be scoped and reviewed.

**Sources:** [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra); [PIM: Privileged Identity Management automation](https://github.com/azurekid/PIM); [PaC: PIM as Code](https://github.com/azurekid/PaC); [Piceb: PIM infrastructure as Bicep](https://github.com/azurekid/Piceb); [Microsoft: PIM role settings](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings); [Microsoft: role-assignable groups](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept); [AzureHacking: Introducing ScEntra](https://azurehacking.com/post/introducing-scentra-an-advanced-permission-visualizer)

### 16. "We enforce MFA" is only half an answer

**HUMAN VS WORKLOAD CONTROLS | 21:00-22:00**

- **Human identities:** Validate policy exclusions, authentication strength, and actual enforcement; use VizCa as supporting analysis.
- **Service principals:** App-only authentication cannot perform MFA; supported workload Conditional Access policies are separate.
- **Managed identities:** Workload Conditional Access does not cover managed identities; protect resource and permission boundaries.

**Land this line:** Ask which identity and which authentication flow the control protects.

Avoid presenting token theft as a universal MFA bypass. Phishing-resistant MFA, session
controls, token protection where supported, and resource enforcement remain important.
Microsoft documents workload Conditional Access for supported single-tenant service principals;
it does not cover managed identities or all multi-tenant applications. It requires applicable
licensing, and service principals must be targeted directly rather than only through a group.
Check current product support when preparing the delivery. Do not infer managed-identity
coverage from a human-user 'all users' policy.
VizCa's static view should be complemented by actual sign-in results and official policy
evaluation. Keep authorized spray testing out of production during the talk.

**Sources:** [Microsoft: Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity); [VizCa: Conditional Access coverage](https://github.com/azurekid/VizCa); [SprayCat: authorized password-spray assessment](https://github.com/azurekid/spraycat)

### 17. The browser terminal inherits the job

**PRACTICAL EXAMPLE 6 / GITHUB ACTIONS SHELL | 22:00-24:00**

- **Your repository:** policy-as-code starts a WebSocket terminal in an Actions job with id-token: write.
- **The identity seam:** The backend spawns Bash with the server's environment; available job authority can cross into the shell.
- **The exposure seam:** A reverse tunnel exposes the terminal; the inspected WebSocket handler has no caller-authentication check.

**Land this line:** A diagnostics shell can become a doorway into workload identity.

This is the user's requested focus: the GitHub Actions interactive shell, not policy use cases.
The inspected OIDC Interactive Shell.yml and git-s-hell.yml start a Node terminal and a reverse
tunnel. assets/terminal_server.js creates a WebSocket.Server and spawns /bin/bash with
env: process.env. Its shown connection handler does not authenticate the caller.
That is a code observation, not proof that an active public endpoint exists or that a real
identity has been compromised. We did not start any workflow, tunnel, or token request.
The workflows declare id-token: write, and git-s-hell explicitly checks for OIDC request
environment availability. The exact runtime/container propagation must still be checked.
The OIDC Interactive Shell workflow also uses a privileged job container; a separate variant
uses --init without that flag. Container root is not proof of root access to the entire host.
Treat shell access, runtime authority, federation acceptance, and Azure access as separate gates.

**Sources:** [GitHub Actions interactive shell workflow](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/OIDC%20Interactive%20Shell.yml); [Interactive Gits hell workflow and OIDC checks](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/git-s-hell.yml); [WebSocket terminal backend and environment inheritance](https://github.com/azurekid/policy-as-code/blob/main/assets/terminal_server.js); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

### 18. Runner shell -> GitHub assertion -> Entra identity

**GITHUB SHELL / FOUR GATES | 24:00-26:00**

- **Gate 1: shell:** A caller reaches the terminal and can execute inside the running job.
- **Gate 2: GitHub:** That job actually has usable OIDC-request capability in the shell runtime.
- **Gate 3:** Entra accepts the assertion's issuer, subject and audience under an existing federated trust.
- **Gate 4:** The resulting Azure/Entra identity is authorized for the requested resource operation.

**Land this line:** id-token: write grants GitHub token-request capability, not Azure permissions.

There is no automatically attached Azure VM managed identity on an ordinary GitHub-hosted
runner. The relevant Azure identity is normally the app or user-assigned managed identity
selected by a valid federated trust. This corrects the shorthand 'attached identity'.
The Azure identifiers in the workflow do not themselves authenticate anything. The inspected
shell workflow has no azure/login step, so it does not prove that Azure CLI is installed or
already signed in. Do not assume an existing Azure access token or Azure session.
OIDC can bridge the gap if the actual job assertion matches a configured trust. Reusable
workflow invocation, caller repository, ref, environment, and customized subject claims matter.
The supplied secure identity template expects an environment-scoped production subject.
The interactive workflows do not declare that environment in their inspected job definitions:
the secure template's trust therefore must not be presumed to match this shell job.
Audience knowledge, shell access, and id-token permission alone cannot create Azure privilege.

**Sources:** [GitHub Actions interactive shell workflow](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/OIDC%20Interactive%20Shell.yml); [Interactive Gits hell workflow and OIDC checks](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/git-s-hell.yml); [Environment-scoped pipeline identity template](https://github.com/azurekid/policy-as-code/blob/main/infra/pipeline-identity.bicep); [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

### 19. Show the capability, never the token

**GITHUB SHELL / DEFENSIVE DEMONSTRATION | 26:00-27:00**

- **Show safely:** A synthetic terminal or approved lab displays only whether OIDC request capability is present.
- **Explain authority:** Identify the trusted principal and its scoped roles from sanitized configuration, not from secret output.
- **Contain the boundary:** Authenticate shell callers; restrict reachability; remove OIDC from diagnostics jobs that do not need it.

**Land this line:** Never print env, bearer tokens, credential caches, or reusable tunnel URLs.

Use the supplied offline model for the talk; the approved-lab plan in the appendix is optional.
The persuasive moment is that the person typing into a browser can be different from the
workflow identity the cloud trusts. You do not need to extract or display a token to explain it.
If a real demonstration is later arranged, use an isolated tenant, dedicated low-privilege
identity, authenticated private terminal access, protected workflow/environment, short duration,
and independent logging. Verify denial of a non-approved operation without altering resources.
Do not launch the repository's current public tunnel or unauthenticated terminal as the demo.
Review whether runtime OIDC variables are available without printing their values, and inspect
pre-sanitized FIC/role configuration. A negative result is useful evidence, not demo failure.
Afterward terminate the job and verify that terminal reachability and issuance capability end;
already issued access tokens may remain usable according to their expiry/enforcement.

**Sources:** [GitHub Actions interactive shell workflow](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/OIDC%20Interactive%20Shell.yml); [WebSocket terminal backend and environment inheritance](https://github.com/azurekid/policy-as-code/blob/main/assets/terminal_server.js); [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

### 20. Whose identity does the connector use?

**PRACTICAL EXAMPLE 7 / CONNECTORS & AGENTS | 27:00-28:00**

- **Misconfiguration:** A Logic App or agent can invoke an overprivileged connection without adequate user-level checks.
- **Identity abuse:** Controlling the invoking workflow may expose the connection's allowed downstream actions.
- **Break the path:** Constrain connector permissions, makers, workflow editors, consent, and caller authorization.

**Land this line:** The user asking and the identity acting may be different.

Use AzureHacking's API Connections and Copilot Studio research as the entry point.
Treat this as a realistic architecture example, not proof that every connector reveals a token
or that prompt injection always grants an administrator role.
Ask four questions: who owns the connection, whose credentials back it, who can invoke it,
and which actions and data are actually authorized downstream?
Separate delegated user permissions from application permissions. A connector mediated by
platform APIs can allow actions without exposing its raw token to the caller.
AgentTrap (whose README calls the project AgentLens), SkillVenom, and skillseal are related
trust-boundary research: agent-file analysis, defanged test cases, and skill approval.
They are not substitutes for Entra access control and are not claimed to be cloud exploit tools.

**Sources:** [AzureHacking: Azure API Connections Deep Dive](https://azurehacking.com/post/azure-api-connections-a-red-team-deep-dive); [AzureHacking: Copilot Studio Detection & Mitigation](https://azurehacking.com/post/copilot-studio-detection-mitigation); [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat)

### 21. Find the edges. Test the gates. Fix the graph.

**YOUR RESEARCH / TOOLING ECOSYSTEM | 28:00-29:00**

- **Discover and validate:** ScEntra maps identity relationships; BlackCat supports authorized Azure security assessments.
- **Close the gaps:** VizCa examines Conditional Access; PIM / PaC / Piceb help manage privileged access.
- **Operationalize evidence:** SigmaXDR, detection-mcp, and DefenderXDR support detection engineering and security operations.

**Land this line:** Use the tools as complementary evidence, not as a security guarantee.

Explain why these projects belong in the same talk: relationships, authorized validation,
governance, and detection form a feedback loop. AzureHacking supplies the research narrative.
Do not claim any repository's current deployment permissions or generated queries are
automatically correct for every product version; evaluate generated content and grant only
the permissions actually needed in your environment.
The appendix accounts for all 61 public repositories found on the research date, including
forks and supporting projects. It does not imply original authorship of forks, exhaustive
code review, or identity relevance for every utility.

**Sources:** [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra); [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat); [VizCa: Conditional Access coverage](https://github.com/azurekid/VizCa); [PIM: Privileged Identity Management automation](https://github.com/azurekid/PIM); [SigmaXDR: detection conversion](https://github.com/azurekid/SigmaXDR); [detection-mcp: detection engineering](https://github.com/azurekid/detection-mcp); [DefenderXDR: security operations automation](https://github.com/azurekid/DefenderXDR); [AzureHacking research website](https://azurehacking.com)

### 22. Watch a trust path disappear

**FIVE-MINUTE OFFLINE DEMO | 29:00-34:00**

- **Before:** Synthetic map: browser terminal -> job OIDC capability -> accepted Entra trust -> scoped resource access.
- **Ask the room:** Which edge would you remove first? What evidence would prove the edge exists?
- **After:** Authenticate terminal callers, remove unneeded job OIDC, and constrain the accepted workload trust.

**Land this line:** No real tokens. No live role changes. The lesson still lands.

Use the dedicated Offline-Demo.html supplied with this deck. It now models the GitHub Actions
interactive-shell identity path, not policy remediation. It contains only synthetic
relationships and requires no cloud login, credentials, dependencies, or network access.
Minute 0-1: show the before state. Identify each principal and permission plane.
Minute 1-2: click each numbered gate and read the prerequisite. Ask for evidence, not guesses.
Minute 2-3: toggle 'After controls'. Three independent gates become blocked.
Minute 3-4: show synthetic events; ask which logs cover each transition.
Minute 4-5: emphasize that this illustrates a model, not successful exploitation of a tenant.
If you have an authorized ScEntra report, you may substitute a sanitized offline screenshot
or report after removing names, IDs, tokens, URLs with secrets, and customer identifiers.
Do not run the intentionally vulnerable app, password spraying, role-writing functions,
shell workflows, or any public tunnel during the presentation.

**Sources:** [GitHub Actions interactive shell workflow](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/OIDC%20Interactive%20Shell.yml); [WebSocket terminal backend and environment inheritance](https://github.com/azurekid/policy-as-code/blob/main/assets/terminal_server.js); [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

### 23. Hunt for changes that create authority

**DETECTION / MICROSOFT SENTINEL | 34:00-36:00**


```kql
AuditLogs
| where TimeGenerated > ago(24h)
| where OperationName has_any
    ("credential", "consent", "permission", "role")
    or OperationName =~ "Update application"
| extend ActorUser = tostring(InitiatedBy.user.id),
         ActorApp = tostring(InitiatedBy.app.servicePrincipalId)
| mv-expand Target = TargetResources
| project TimeGenerated, OperationName, Result,
          ActorUser, ActorApp,
          TargetId = tostring(Target.id),
          TargetName = tostring(Target.displayName)
| order by TimeGenerated desc
```
This hunt surfaces authority-related audit changes and their actors/targets.

**Land this line:** Broad hunt, not a production-ready analytic. Tune from actual tenant events.

Explain the Kusto Query Language (KQL) immediately after showing it: this broad hunt surfaces
credential-, consent-, permission-, and role-related audit operations, with actor and target IDs.
It also includes generic Update application events, whose modified properties require inspection.
It does not prove malicious intent, cover every identity change, or detect managed-identity FIC
changes that are logged in Azure Activity rather than Entra AuditLogs.
Prerequisite: Entra audit logs are ingested into a Microsoft Sentinel Log Analytics workspace.
AuditLogs, InitiatedBy, TargetResources, OperationName, TimeGenerated, and Result are documented
schema fields. mv-expand may produce multiple rows per audit operation; count distinct event
IDs if turning this into rate-based logic. The displayed query is for inspection, not counting.
Validate operation names and modifiedProperties in your tenant; tune authorized administrators
and change windows rather than blindly suppressing every deployment identity.
The query was checked against documented schemas but not executed against a real workspace.

**Sources:** [Microsoft: AuditLogs schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/auditlogs); [AzureHacking: Detecting Privilege Escalation in Entra ID](https://azurehacking.com/post/detecting-privilege-escalation-in-entra-id); [SigmaXDR: detection conversion](https://github.com/azurekid/SigmaXDR); [detection-mcp: detection engineering](https://github.com/azurekid/detection-mcp)

### 24. One identity chain, several evidence sources

**DETECTION / JOIN THE PERMISSION PLANES | 36:00-37:00**

- **Entra:** AuditLogs + user, service principal, and managed identity sign-ins + PIM activation records.
- **Azure and data:** AzureActivity for resource/trust changes; Key Vault, Storage, and workload resource logs for actual access.
- **Delivery platform:** GitHub workflow/environment audit and execution evidence identify who controlled the trusted code.

**Land this line:** Correlate stable IDs and time. Never assume one cross-service correlation ID.

Distinguish object IDs from app IDs, UPNs, and display names; display names alone are poor join keys.
Service-principal sign-ins indicate token acquisition and may be aggregated; they do not
document every subsequent API use. Managed identity sign-ins have their own table/category
when exported. Avoid claiming that every token replay produces a fresh sign-in event.
Correlate a credential or trust change with token acquisition and downstream operations,
allowing for log latency. Preserve each service's own correlation IDs, but do not assume
one global ID follows the full attack chain.
AzureHacking's diagnostic-setting article is the defensive twist: health metrics can continue
while selected resource logs stop reaching your SIEM. This does not erase Azure's platform
Activity Log or all Entra telemetry. Monitor configuration drift, destination integrity,
and expected log-category freshness separately.

**Sources:** [Microsoft: AuditLogs schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/auditlogs); [Microsoft: service principal sign-in schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/aadserviceprincipalsigninlogs); [AzureHacking: Diagnostic Setting Manipulation](https://azurehacking.com/post/impairing-azure-defenses-through-diagnostic-setting-manipulation); [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat)

### 25. Resetting the first password is not enough

**RESPONSE / EVICT THE AUTHORITY | 37:00-38:00**

- **Contain safely:** Use trusted administration; preserve evidence; isolate the affected workload or automation path.
- **Remove recurring access:** Revoke exposed credentials and unauthorized grants, trust entries, ownership, and role assignments.
- **Verify recovery:** Test denied paths, restored logging, affected data scope, and remaining token/session exposure.

**Land this line:** Close every route that can mint or exercise the identity.

Coordinate containment with incident response and service owners so necessary production
services are not inadvertently destroyed. Preserve relevant logs and original configurations.
Revoking a password is not the same as removing an app secret, app-role grant, FIC, or
compromised managed-identity runtime. Rotate and revoke the specific authorities in the path.
Do not promise instant invalidation of every access token. Expiry, resource enforcement,
Continuous Access Evaluation where supported, caching, and propagation vary by flow and service.
Re-authenticate from trusted systems, verify effective access after propagation, and check
the data plane for use of already issued tokens. Review recovery identities and emergency
access before closing broad routes. Treat stolen data as a separate impact workstream.

**Sources:** [Microsoft responder guidance, 25 January 2024](https://www.microsoft.com/en-us/security/blog/2024/01/25/midnight-blizzard-guidance-for-responders-on-nation-state-attack/); [Microsoft: Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity); [Microsoft: managed identity security boundary](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq)

### 26. Five changes worth making first

**PREVENTION / TOMORROW MORNING | 38:00-39:00**

- **1 / 2:** Inventory human and workload identities with owners; remove unused credentials, grants, and stale trust.
- **3 / 4:** Protect credential/trust writers and privileged runtimes; scope both deployment and execution identities.
- **5:** Prove coverage with synthetic changes, PIM gates, denied-path checks, and log-freshness monitoring.

**Land this line:** Start with identities that can grant, impersonate, deploy, or change trust.

Make the takeaway concrete without prescribing a destructive one-click cleanup.
Start with high-impact Graph application permissions, applications whose credentials can be
edited by lower-trust users, managed identities shared across unlike workloads, policy
remediation identities, and Conditional Access exclusions.
Assign a business owner, scope, credential/trust inventory, activation requirements, and
expected usage to each high-impact identity. Separate ordinary operations from privilege grants.
Use ScEntra and BlackCat to support authorized validation, VizCa for coverage analysis,
PIM-family projects for governance, and detection tools for an evidence loop.
Set measurable goals that fit your organization, rather than inventing universal risk scores.

**Sources:** [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra); [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat); [VizCa: Conditional Access coverage](https://github.com/azurekid/VizCa); [PIM: Privileged Identity Management automation](https://github.com/azurekid/PIM); [AzureHacking: Detecting Privilege Escalation in Entra ID](https://azurehacking.com/post/detecting-privilege-escalation-in-entra-id)

### 27. Who can become this identity?

**CLOSING / AZUREHACKING | 39:00-40:00**

- **Not just:** 'Who has Global Administrator today?'
- **Also ask:** 'Who can edit its app, run its code, change its trust, or activate its privileges?'
- **Take action:** Explore AzureHacking's tenant-takeover research and map one authorized path with ScEntra.

**Land this line:** The attack path is your architecture, viewed from the wrong end.

Return to the opening document. The problem was not merely a file: it was the chain of
authority the file made reachable.
Summarize in one sentence: protect the relationships that let weaker components become
stronger identities. Do not turn this into a long checklist recap.
The call to action is to visit AzureHacking's tenant-takeover research and assess a single
authorized identity path, checking every permission gate. The final slide intentionally links
to the website and ScEntra instead of ending with exploit commands.
The website URLs use the current /post/ form where confirmed by the source sitemap.

**Sources:** [AzureHacking research website](https://azurehacking.com); [AzureHacking: Azure Tenant Takeover](https://azurehacking.com/post/azure-tenant-takeover-from-exposed-config-to-global-admin); [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra)

### 28. Which trusted identity worries you most?

**DISCUSSION / FIVE MINUTES | 40:00-45:00**

- **Architecture:** Where can code, credentials, group control, or workflow control cross a privilege boundary?
- **Detection:** Which transition would be invisible in your current telemetry?
- **Ownership:** Who is accountable for the identity and every path that can become it?

**Land this line:** Test the path you actually have, not the one a diagram promises.

Reserve five minutes for audience questions. Good prompts include test-to-production trust,
managed identity boundaries, standard federation matching, PIM activation gates, and data-plane
evidence. If asked for a live exploitation procedure, keep the conversation within authorized
lab assessment and refer to the projects' documentation without exposing real credentials.
Use the appendices for the complete project inventory, extra workload hunt, sources, and
technical qualifications. The 35-minute narrative plus five-minute offline demo totals
40 minutes before this five-minute discussion.

**Sources:** [AzureHacking research website](https://azurehacking.com)

### 29. New successful service-principal / IP pairs

**APPENDIX / OPTIONAL WORKLOAD HUNT | Appendix / optional**


```kql
let Recent =
    AADServicePrincipalSignInLogs
    | where TimeGenerated > ago(1d) and ResultType == "0";
let KnownPairs =
    AADServicePrincipalSignInLogs
    | where TimeGenerated between (ago(15d) .. ago(1d))
        and ResultType == "0"
    | distinct ServicePrincipalId, IPAddress;
Recent
| join kind=leftanti KnownPairs on ServicePrincipalId, IPAddress
| project TimeGenerated, ServicePrincipalId, AppId,
          IPAddress, ResourceDisplayName
```
This hunt identifies successful service-principal/IP pairs absent from the preceding baseline.

**Land this line:** A novelty signal, not a verdict. New IPs can be legitimate.

This KQL compares successful service-principal sign-ins from the last day against the
preceding fourteen days. It returns identity/IP pairs absent from that baseline.
It is not a managed-identity detection, and it does not establish token replay.
Prerequisites: the named sign-in table is ingested and the full baseline is available.
The query uses documented columns and string ResultType. A new identity, sparse history,
NAT change, proxy, hosted runner, or legitimate deployment can trigger it.
Tune against approved workload locations and expected resource access, then correlate
with audit and Azure/data-plane evidence. Do not treat IP geography as identity proof.
Like the audit query, this is a schema-reviewed example, not tenant-executed KQL.

**Sources:** [Microsoft: service principal sign-in schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/aadserviceprincipalsigninlogs); [detection-mcp: detection engineering](https://github.com/azurekid/detection-mcp); [SigmaXDR: detection conversion](https://github.com/azurekid/SigmaXDR)

### 30. Do not turn these into universal shortcuts

**APPENDIX / TECHNICAL QUALIFICATIONS | Appendix / optional**

- **Storage and federation:** Retained data is not automatically anonymously readable; standard FIC subjects are exact matches.
- **Roles and groups:** Contributor cannot directly assign Owner; ordinary group administration is not control of role-assignable groups.
- **Tokens and telemetry:** MFA is not universally bypassed; token acquisition is not every API call; selected log loss is not all log loss.

**Land this line:** Source examples are inspiration; effective authorization is the authority.

These qualifications address ambiguities in source demonstrations and common presentation
overclaims. They are included deliberately so the deck does not repeat an attractive but
invalid escalation path.
Graph app roles, Entra directory roles, Azure Actions/DataActions, consent requirements,
PIM eligibility/activation, resource execution rights, and federation authorization all
need to be assessed separately. A denied operation is an expected possible result.
The website catalogue and repository README claims are attributed research references;
Microsoft documentation supplies the platform constraints used in this presentation.

**Sources:** [Microsoft: managing soft-deleted blobs](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-manage); [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [Microsoft: Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles); [Microsoft: role-assignable groups](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept); [Microsoft: Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity); [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)

### 31. Validate presence without exposing credentials

**APPENDIX / OPTIONAL APPROVED-LAB CHECK | Appendix / optional**


```bash
# Approved isolated lab only; never dump the environment.
if [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] &&
   [ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  printf 'OIDC request environment: present\n'
else
  printf 'OIDC request environment: absent\n'
fi
# Presence is NOT proof of an accepted Entra trust or Azure access.
# Review sanitized FIC + effective role scope separately.
# Do not request, print, copy, or replay tokens for this demo.
```
This check reports only OIDC environment presence; it neither requests nor prints tokens.

**Land this line:** No token request is made. Presence alone does not prove usable authority.

This Bash snippet is only a non-disclosing environment-presence check, not an exploit.
Do not paste it into an untrusted shell or create a public terminal to run it.
Use only an independently approved private lab. The default supplied demonstration is offline.
The snippet does not verify token endpoint responsiveness, federated trust acceptance,
or downstream authorization. Those gates need separate approved evidence.
Never print full environment variables, the OIDC request token, a returned assertion,
Azure bearer tokens, cached sessions, secrets, or the public tunnel URL.

**Sources:** [Interactive Gits hell workflow and OIDC checks](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/git-s-hell.yml); [WebSocket terminal backend and environment inheritance](https://github.com/azurekid/policy-as-code/blob/main/assets/terminal_server.js); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

### 32. Identity assessment and access governance

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **blackcat:** Authorized Azure assessment and identity-path validation
- **ScEntra:** Entra permissions, role relationships, and escalation graphs
- **spraycat:** Authorized human-account password-spray assessment
- **VizCa:** Conditional Access visualization and coverage analysis
- **PIM:** Privileged Identity Management PowerShell automation
- **PaC:** PIM as Code PowerShell automation
- **Piceb:** PIM deployment and management using Bicep
- **AzurePermissionInsight:** Fork: Azure RBAC permission insight
- **AADInternals:** Fork: Entra/Azure AD administration and research toolkit

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 33. Training, demos, and identity-backed apps

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **mc2-connect:** Explicit Blue Mountain Travel tenant-takeover tabletop
- **mc2connect:** Empty repository; no implementation verified
- **bluemountaintravel:** Intentionally vulnerable security-training application
- **bluemountainbank:** Demo-named project; sparse README, no identity claims inferred
- **policy-as-code:** Actions interactive shell, job OIDC, and identity trust demo
- **operation-blackcat:** Challenge repository; includes Operation Esprit
- **azure-opt:** Azure one-time-password solution, per repository description
- **key-vault-function:** Function for registering data in Azure Key Vault
- **AzShortLink:** Azure Functions URL shortener with local identity and auditing
- **ParcelPinPoint:** Parcel pickup/drop-off web application

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 34. Detection, telemetry, and security operations

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **DefenderXDR:** PowerShell security operations and hunting automation
- **SigmaXDR:** Sigma-to-Defender-XDR detection conversion
- **detection-mcp:** MCP-based detection conversion and deployment tooling
- **Azure-Sentinel:** Fork: Microsoft Sentinel detection/community content
- **sigma:** Fork: Sigma detection rules
- **1Password-Sentinel:** 1Password integration in Sentinel solution directories
- **KeepIt:** KeepIt audit integration, ingestion, and Sentinel normalization
- **Microsoft-Defender-for-Cloud:** Fork: Defender for Cloud community content
- **Copilot-For-Security:** Fork: Microsoft Security Copilot community content

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 35. Agent trust and supporting security tools

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **AgentTrap:** README names AgentLens: static AI-agent-file scanner
- **SkillVenom:** Defanged, test-backed agent-file attack catalogue
- **skillseal:** Signed/approved agent-skill enforcement
- **warstick:** Portable AI assistant capable of local command execution
- **HashSight:** Hash-type identification/intelligence utility
- **SQLizer:** Authorized web/database vulnerability testing tool
- **fastbuster:** Fast web discovery utility; supporting recon, not identity proof
- **shadowcat:** Windows security research platform

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 36. Governance, infrastructure, and research labs

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **template-analyzer:** Fork: infrastructure template security analysis
- **cloud-custodian:** Fork: cloud policy and governance rules engine
- **azure-orphan-resources:** Fork: orphaned-resource inventory
- **Azure-Lighthouse-samples:** Fork: delegated resource management samples
- **Bio-Compliancy:** Fork: Dutch BIO compliance initiative
- **Microsoft-Sentinel2Go:** Fork: Sentinel research-lab deployment
- **Sentinel-playground:** Fork: Sentinel proof-of-concept/demo environment
- **sentinel-deploy:** Deployment/template starter; sparse template README
- **steampipe:** Fork: SQL-based cloud-service inventory/query tooling

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 37. Platform references, utilities, and learning

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **azure-docs:** Fork: Microsoft Azure documentation
- **azure-powershell:** Fork: Microsoft Azure PowerShell
- **azure-resource-manager-schemas:** Fork: ARM template schemas
- **Azure-Stencils:** Azure diagram icons and stencils
- **jsonize:** JSON formatting helper
- **blog:** Supporting blog scripts, templates, and historical assets
- **extensions:** DevOps extensions, per repository description
- **codespaces:** Codespaces starter template
- **pester-tests-report:** Fork: GitHub Action for Pester test reports
- **doodle-to-code:** Fork: generative AI learning material

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 38. Profile and remaining learning/support projects

**APPENDIX / ALL PUBLIC PROJECTS | Appendix / optional**

- **azurekid:** Profile repository
- **skills-copilot-codespaces-vscode:** GitHub Copilot learning exercise
- **skills-code-with-codespaces:** Codespaces learning exercise
- **skills-introduction-to-github:** GitHub introduction exercise
- **linkedin-skill-assessments-quizzes:** Fork: assessment/learning reference; not identity research
- **r1ckr0ll3r:** Novelty website; not identity research

**Land this line:** 61 public repositories reviewed at catalogue/README level; forks are identified.

The inventory includes every public repository returned for azurekid on 9 November 2026.
Descriptions are based on repository metadata, README summaries, or directory listings,
not a complete source-code audit. Sparse and empty projects are identified conservatively.
Forks belong to their original upstream authors and are not presented as original tools.
These are supporting references, not a requirement to use unrelated projects in the main story.

### 39. Incident evidence and identity boundaries

**APPENDIX / CLICKABLE REFERENCES | Appendix / optional**

- **MS1:** Microsoft incident disclosure, 19 January 2024
- **MS2:** Microsoft responder guidance, 25 January 2024
- **MS3:** Microsoft incident update, 8 March 2024
- **MI:** Microsoft: managed identity security boundary
- **FIC:** Microsoft: workload identity federation
- **CA:** Microsoft: Conditional Access for workload identities
- **APP:** Microsoft: Application Administrator permissions

**Land this line:** Full URLs and slide-by-slide citations are in Speaker-Notes.md.

Source links are clickable in PowerPoint and the browser deck.
Microsoft incident disclosures were corroborated through indexed official pages.
AzureHacking's live hostname did not resolve from this environment. Its public article
catalogue and canonical paths were recovered from the site's source llms.txt and sitemap.
An archived, published diagnostic-setting article was also read; full text of every
other article was not independently retrieved. Do not imply otherwise.
Website reachability and content may change; recheck links before public delivery.

**Sources:** [Microsoft incident disclosure, 19 January 2024](https://www.microsoft.com/en-us/msrc/blog/2024/01/microsoft-actions-following-attack-by-nation-state-actor-midnight-blizzard); [Microsoft responder guidance, 25 January 2024](https://www.microsoft.com/en-us/security/blog/2024/01/25/midnight-blizzard-guidance-for-responders-on-nation-state-attack/); [Microsoft incident update, 8 March 2024](https://www.microsoft.com/en-us/msrc/blog/2024/03/update-on-microsoft-actions-following-attack-by-nation-state-actor-midnight-blizzard); [Microsoft: managed identity security boundary](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq); [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [Microsoft: Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity); [Microsoft: Application Administrator permissions](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#application-administrator)

### 40. Authorization, governance, and detection schemas

**APPENDIX / CLICKABLE REFERENCES | Appendix / optional**

- **GRAPH:** Microsoft Graph permissions reference
- **RBAC:** Microsoft: Azure built-in roles
- **KV:** Microsoft: Key Vault RBAC
- **PIMDOC:** Microsoft: PIM role settings
- **GROUP:** Microsoft: role-assignable groups
- **POLICYDOC:** Microsoft: Azure Policy remediation identities
- **OIDC:** GitHub: OpenID Connect in Azure
- **STORAGE:** Microsoft: managing soft-deleted blobs
- **AUDIT:** Microsoft: AuditLogs schema
- **SPLOG:** Microsoft: service principal sign-in schema
- **MITRE:** MITRE: Cloud Accounts (T1078.004)

**Land this line:** Full URLs and slide-by-slide citations are in Speaker-Notes.md.

Source links are clickable in PowerPoint and the browser deck.
Microsoft incident disclosures were corroborated through indexed official pages.
AzureHacking's live hostname did not resolve from this environment. Its public article
catalogue and canonical paths were recovered from the site's source llms.txt and sitemap.
An archived, published diagnostic-setting article was also read; full text of every
other article was not independently retrieved. Do not imply otherwise.
Website reachability and content may change; recheck links before public delivery.

**Sources:** [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference); [Microsoft: Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles); [Microsoft: Key Vault RBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide); [Microsoft: PIM role settings](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings); [Microsoft: role-assignable groups](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept); [Microsoft: Azure Policy remediation identities](https://learn.microsoft.com/en-us/azure/governance/policy/how-to/remediate-resources); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure); [Microsoft: managing soft-deleted blobs](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-manage); [Microsoft: AuditLogs schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/auditlogs); [Microsoft: service principal sign-in schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/aadserviceprincipalsigninlogs); [MITRE: Cloud Accounts (T1078.004)](https://attack.mitre.org/techniques/T1078/004/)

### 41. AzureHacking research used in the narrative

**APPENDIX / CLICKABLE REFERENCES | Appendix / optional**

- **AH:** AzureHacking research website
- **AHCHAIN:** AzureHacking: Azure Tenant Takeover
- **AHSC:** AzureHacking: Introducing ScEntra
- **AHESC:** AzureHacking: Detecting Privilege Escalation in Entra ID
- **AHFIC:** AzureHacking: Federated Identity Credential Injection
- **AHKV:** AzureHacking: Azure Key Vault Security Deep Dive
- **AHCON:** AzureHacking: Azure API Connections Deep Dive
- **AHCOP:** AzureHacking: Copilot Studio Detection & Mitigation
- **AHLOG:** AzureHacking: Diagnostic Setting Manipulation

**Land this line:** Full URLs and slide-by-slide citations are in Speaker-Notes.md.

Source links are clickable in PowerPoint and the browser deck.
Microsoft incident disclosures were corroborated through indexed official pages.
AzureHacking's live hostname did not resolve from this environment. Its public article
catalogue and canonical paths were recovered from the site's source llms.txt and sitemap.
An archived, published diagnostic-setting article was also read; full text of every
other article was not independently retrieved. Do not imply otherwise.
Website reachability and content may change; recheck links before public delivery.

**Sources:** [AzureHacking research website](https://azurehacking.com); [AzureHacking: Azure Tenant Takeover](https://azurehacking.com/post/azure-tenant-takeover-from-exposed-config-to-global-admin); [AzureHacking: Introducing ScEntra](https://azurehacking.com/post/introducing-scentra-an-advanced-permission-visualizer); [AzureHacking: Detecting Privilege Escalation in Entra ID](https://azurehacking.com/post/detecting-privilege-escalation-in-entra-id); [AzureHacking: Federated Identity Credential Injection](https://azurehacking.com/post/federated-identity-credential-injection-proof-of-concept); [AzureHacking: Azure Key Vault Security Deep Dive](https://azurehacking.com/post/azure-key-vault-security-deep-dive); [AzureHacking: Azure API Connections Deep Dive](https://azurehacking.com/post/azure-api-connections-a-red-team-deep-dive); [AzureHacking: Copilot Studio Detection & Mitigation](https://azurehacking.com/post/copilot-studio-detection-mitigation); [AzureHacking: Diagnostic Setting Manipulation](https://azurehacking.com/post/impairing-azure-defenses-through-diagnostic-setting-manipulation)

### 42. Original project references

**APPENDIX / CLICKABLE REFERENCES | Appendix / optional**

- **BC:** BlackCat: Azure security assessment module
- **SC:** ScEntra: identity relationships and escalation paths
- **VC:** VizCa: Conditional Access coverage
- **SPRAY:** SprayCat: authorized password-spray assessment
- **MC:** Blue Mountain Travel tenant-takeover tabletop
- **BMT:** Blue Mountain Travel: intentionally vulnerable training app
- **POL:** Policy-as-Code identity demonstration
- **PIM:** PIM: Privileged Identity Management automation
- **PAC:** PaC: PIM as Code
- **PIC:** Piceb: PIM infrastructure as Bicep
- **SIG:** SigmaXDR: detection conversion
- **DET:** detection-mcp: detection engineering
- **XDR:** DefenderXDR: security operations automation

**Land this line:** Full URLs and slide-by-slide citations are in Speaker-Notes.md.

Source links are clickable in PowerPoint and the browser deck.
Microsoft incident disclosures were corroborated through indexed official pages.
AzureHacking's live hostname did not resolve from this environment. Its public article
catalogue and canonical paths were recovered from the site's source llms.txt and sitemap.
An archived, published diagnostic-setting article was also read; full text of every
other article was not independently retrieved. Do not imply otherwise.
Website reachability and content may change; recheck links before public delivery.

**Sources:** [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat); [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra); [VizCa: Conditional Access coverage](https://github.com/azurekid/VizCa); [SprayCat: authorized password-spray assessment](https://github.com/azurekid/spraycat); [Blue Mountain Travel tenant-takeover tabletop](https://github.com/azurekid/mc2-connect); [Blue Mountain Travel: intentionally vulnerable training app](https://github.com/azurekid/bluemountaintravel); [Policy-as-Code identity demonstration](https://github.com/azurekid/policy-as-code); [PIM: Privileged Identity Management automation](https://github.com/azurekid/PIM); [PaC: PIM as Code](https://github.com/azurekid/PaC); [Piceb: PIM infrastructure as Bicep](https://github.com/azurekid/Piceb); [SigmaXDR: detection conversion](https://github.com/azurekid/SigmaXDR); [detection-mcp: detection engineering](https://github.com/azurekid/detection-mcp); [DefenderXDR: security operations automation](https://github.com/azurekid/DefenderXDR)

### 43. Interactive shell: inspected source and identity gates

**APPENDIX / CLICKABLE REFERENCES | Appendix / optional**

- **SHELL:** GitHub Actions interactive shell workflow
- **GITSHELL:** Interactive Gits hell workflow and OIDC checks
- **TERM:** WebSocket terminal backend and environment inheritance
- **BASELINE:** Environment-scoped pipeline identity template
- **FIC:** Microsoft: workload identity federation
- **OIDC:** GitHub: OpenID Connect in Azure

**Land this line:** Full URLs and slide-by-slide citations are in Speaker-Notes.md.

Source links are clickable in PowerPoint and the browser deck.
Microsoft incident disclosures were corroborated through indexed official pages.
AzureHacking's live hostname did not resolve from this environment. Its public article
catalogue and canonical paths were recovered from the site's source llms.txt and sitemap.
An archived, published diagnostic-setting article was also read; full text of every
other article was not independently retrieved. Do not imply otherwise.
Website reachability and content may change; recheck links before public delivery.

**Sources:** [GitHub Actions interactive shell workflow](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/OIDC%20Interactive%20Shell.yml); [Interactive Gits hell workflow and OIDC checks](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/git-s-hell.yml); [WebSocket terminal backend and environment inheritance](https://github.com/azurekid/policy-as-code/blob/main/assets/terminal_server.js); [Environment-scoped pipeline identity template](https://github.com/azurekid/policy-as-code/blob/main/infra/pipeline-identity.bicep); [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation); [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

## Complete public project inventory

| Project | Type | Presentation relevance / verified scope |
|---|---|---|
| [1Password-Sentinel](https://github.com/azurekid/1Password-Sentinel) | Non-fork | 1Password integration in Sentinel solution directories |
| [AADInternals](https://github.com/azurekid/AADInternals) | Fork | Fork: Entra/Azure AD administration and research toolkit |
| [AgentTrap](https://github.com/azurekid/AgentTrap) | Non-fork | README names AgentLens: static AI-agent-file scanner |
| [AzShortLink](https://github.com/azurekid/AzShortLink) | Non-fork | Azure Functions URL shortener with local identity and auditing |
| [azure-docs](https://github.com/azurekid/azure-docs) | Fork | Fork: Microsoft Azure documentation |
| [Azure-Lighthouse-samples](https://github.com/azurekid/Azure-Lighthouse-samples) | Fork | Fork: delegated resource management samples |
| [azure-opt](https://github.com/azurekid/azure-opt) | Non-fork | Azure one-time-password solution, per repository description |
| [azure-orphan-resources](https://github.com/azurekid/azure-orphan-resources) | Fork | Fork: orphaned-resource inventory |
| [azure-powershell](https://github.com/azurekid/azure-powershell) | Fork | Fork: Microsoft Azure PowerShell |
| [azure-resource-manager-schemas](https://github.com/azurekid/azure-resource-manager-schemas) | Fork | Fork: ARM template schemas |
| [Azure-Sentinel](https://github.com/azurekid/Azure-Sentinel) | Fork | Fork: Microsoft Sentinel detection/community content |
| [Azure-Stencils](https://github.com/azurekid/Azure-Stencils) | Non-fork | Azure diagram icons and stencils |
| [azurekid](https://github.com/azurekid/azurekid) | Non-fork | Profile repository |
| [AzurePermissionInsight](https://github.com/azurekid/AzurePermissionInsight) | Fork | Fork: Azure RBAC permission insight |
| [Bio-Compliancy](https://github.com/azurekid/Bio-Compliancy) | Fork | Fork: Dutch BIO compliance initiative |
| [blackcat](https://github.com/azurekid/blackcat) | Non-fork | Authorized Azure assessment and identity-path validation |
| [blog](https://github.com/azurekid/blog) | Non-fork | Supporting blog scripts, templates, and historical assets |
| [bluemountainbank](https://github.com/azurekid/bluemountainbank) | Non-fork | Demo-named project; sparse README, no identity claims inferred |
| [bluemountaintravel](https://github.com/azurekid/bluemountaintravel) | Non-fork | Intentionally vulnerable security-training application |
| [cloud-custodian](https://github.com/azurekid/cloud-custodian) | Fork | Fork: cloud policy and governance rules engine |
| [codespaces](https://github.com/azurekid/codespaces) | Non-fork | Codespaces starter template |
| [Copilot-For-Security](https://github.com/azurekid/Copilot-For-Security) | Fork | Fork: Microsoft Security Copilot community content |
| [DefenderXDR](https://github.com/azurekid/DefenderXDR) | Non-fork | PowerShell security operations and hunting automation |
| [detection-mcp](https://github.com/azurekid/detection-mcp) | Non-fork | MCP-based detection conversion and deployment tooling |
| [doodle-to-code](https://github.com/azurekid/doodle-to-code) | Fork | Fork: generative AI learning material |
| [extensions](https://github.com/azurekid/extensions) | Non-fork | DevOps extensions, per repository description |
| [fastbuster](https://github.com/azurekid/fastbuster) | Non-fork | Fast web discovery utility; supporting recon, not identity proof |
| [HashSight](https://github.com/azurekid/HashSight) | Non-fork | Hash-type identification/intelligence utility |
| [jsonize](https://github.com/azurekid/jsonize) | Non-fork | JSON formatting helper |
| [KeepIt](https://github.com/azurekid/KeepIt) | Non-fork | KeepIt audit integration, ingestion, and Sentinel normalization |
| [key-vault-function](https://github.com/azurekid/key-vault-function) | Non-fork | Function for registering data in Azure Key Vault |
| [linkedin-skill-assessments-quizzes](https://github.com/azurekid/linkedin-skill-assessments-quizzes) | Fork | Fork: assessment/learning reference; not identity research |
| [mc2-connect](https://github.com/azurekid/mc2-connect) | Non-fork | Explicit Blue Mountain Travel tenant-takeover tabletop |
| [mc2connect](https://github.com/azurekid/mc2connect) | Non-fork | Empty repository; no implementation verified |
| [Microsoft-Defender-for-Cloud](https://github.com/azurekid/Microsoft-Defender-for-Cloud) | Fork | Fork: Defender for Cloud community content |
| [Microsoft-Sentinel2Go](https://github.com/azurekid/Microsoft-Sentinel2Go) | Fork | Fork: Sentinel research-lab deployment |
| [operation-blackcat](https://github.com/azurekid/operation-blackcat) | Non-fork | Challenge repository; includes Operation Esprit |
| [PaC](https://github.com/azurekid/PaC) | Non-fork | PIM as Code PowerShell automation |
| [ParcelPinPoint](https://github.com/azurekid/ParcelPinPoint) | Non-fork | Parcel pickup/drop-off web application |
| [pester-tests-report](https://github.com/azurekid/pester-tests-report) | Fork | Fork: GitHub Action for Pester test reports |
| [Piceb](https://github.com/azurekid/Piceb) | Non-fork | PIM deployment and management using Bicep |
| [PIM](https://github.com/azurekid/PIM) | Non-fork | Privileged Identity Management PowerShell automation |
| [policy-as-code](https://github.com/azurekid/policy-as-code) | Non-fork | Actions interactive shell, job OIDC, and identity trust demo |
| [r1ckr0ll3r](https://github.com/azurekid/r1ckr0ll3r) | Non-fork | Novelty website; not identity research |
| [ScEntra](https://github.com/azurekid/ScEntra) | Non-fork | Entra permissions, role relationships, and escalation graphs |
| [sentinel-deploy](https://github.com/azurekid/sentinel-deploy) | Non-fork | Deployment/template starter; sparse template README |
| [Sentinel-playground](https://github.com/azurekid/Sentinel-playground) | Fork | Fork: Sentinel proof-of-concept/demo environment |
| [shadowcat](https://github.com/azurekid/shadowcat) | Non-fork | Windows security research platform |
| [sigma](https://github.com/azurekid/sigma) | Fork | Fork: Sigma detection rules |
| [SigmaXDR](https://github.com/azurekid/SigmaXDR) | Non-fork | Sigma-to-Defender-XDR detection conversion |
| [skills-code-with-codespaces](https://github.com/azurekid/skills-code-with-codespaces) | Non-fork | Codespaces learning exercise |
| [skills-copilot-codespaces-vscode](https://github.com/azurekid/skills-copilot-codespaces-vscode) | Non-fork | GitHub Copilot learning exercise |
| [skills-introduction-to-github](https://github.com/azurekid/skills-introduction-to-github) | Non-fork | GitHub introduction exercise |
| [skillseal](https://github.com/azurekid/skillseal) | Non-fork | Signed/approved agent-skill enforcement |
| [SkillVenom](https://github.com/azurekid/SkillVenom) | Non-fork | Defanged, test-backed agent-file attack catalogue |
| [spraycat](https://github.com/azurekid/spraycat) | Non-fork | Authorized human-account password-spray assessment |
| [SQLizer](https://github.com/azurekid/SQLizer) | Non-fork | Authorized web/database vulnerability testing tool |
| [steampipe](https://github.com/azurekid/steampipe) | Fork | Fork: SQL-based cloud-service inventory/query tooling |
| [template-analyzer](https://github.com/azurekid/template-analyzer) | Fork | Fork: infrastructure template security analysis |
| [VizCa](https://github.com/azurekid/VizCa) | Non-fork | Conditional Access visualization and coverage analysis |
| [warstick](https://github.com/azurekid/warstick) | Non-fork | Portable AI assistant capable of local command execution |

## Source bibliography

- **[MS1]** [Microsoft incident disclosure, 19 January 2024](https://www.microsoft.com/en-us/msrc/blog/2024/01/microsoft-actions-following-attack-by-nation-state-actor-midnight-blizzard)
- **[MS2]** [Microsoft responder guidance, 25 January 2024](https://www.microsoft.com/en-us/security/blog/2024/01/25/midnight-blizzard-guidance-for-responders-on-nation-state-attack/)
- **[MS3]** [Microsoft incident update, 8 March 2024](https://www.microsoft.com/en-us/msrc/blog/2024/03/update-on-microsoft-actions-following-attack-by-nation-state-actor-midnight-blizzard)
- **[MI]** [Microsoft: managed identity security boundary](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq)
- **[FIC]** [Microsoft: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
- **[CA]** [Microsoft: Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity)
- **[APP]** [Microsoft: Application Administrator permissions](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#application-administrator)
- **[GRAPH]** [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- **[RBAC]** [Microsoft: Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
- **[KV]** [Microsoft: Key Vault RBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- **[PIMDOC]** [Microsoft: PIM role settings](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)
- **[GROUP]** [Microsoft: role-assignable groups](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept)
- **[POLICYDOC]** [Microsoft: Azure Policy remediation identities](https://learn.microsoft.com/en-us/azure/governance/policy/how-to/remediate-resources)
- **[OIDC]** [GitHub: OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- **[STORAGE]** [Microsoft: managing soft-deleted blobs](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-manage)
- **[AUDIT]** [Microsoft: AuditLogs schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/auditlogs)
- **[SPLOG]** [Microsoft: service principal sign-in schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/aadserviceprincipalsigninlogs)
- **[MITRE]** [MITRE: Cloud Accounts (T1078.004)](https://attack.mitre.org/techniques/T1078/004/)
- **[BC]** [BlackCat: Azure security assessment module](https://github.com/azurekid/blackcat)
- **[SC]** [ScEntra: identity relationships and escalation paths](https://github.com/azurekid/ScEntra)
- **[VC]** [VizCa: Conditional Access coverage](https://github.com/azurekid/VizCa)
- **[SPRAY]** [SprayCat: authorized password-spray assessment](https://github.com/azurekid/spraycat)
- **[MC]** [Blue Mountain Travel tenant-takeover tabletop](https://github.com/azurekid/mc2-connect)
- **[BMT]** [Blue Mountain Travel: intentionally vulnerable training app](https://github.com/azurekid/bluemountaintravel)
- **[POL]** [Policy-as-Code identity demonstration](https://github.com/azurekid/policy-as-code)
- **[SHELL]** [GitHub Actions interactive shell workflow](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/OIDC%20Interactive%20Shell.yml)
- **[GITSHELL]** [Interactive Gits hell workflow and OIDC checks](https://github.com/azurekid/policy-as-code/blob/main/.github/workflows/git-s-hell.yml)
- **[TERM]** [WebSocket terminal backend and environment inheritance](https://github.com/azurekid/policy-as-code/blob/main/assets/terminal_server.js)
- **[BASELINE]** [Environment-scoped pipeline identity template](https://github.com/azurekid/policy-as-code/blob/main/infra/pipeline-identity.bicep)
- **[PIM]** [PIM: Privileged Identity Management automation](https://github.com/azurekid/PIM)
- **[PAC]** [PaC: PIM as Code](https://github.com/azurekid/PaC)
- **[PIC]** [Piceb: PIM infrastructure as Bicep](https://github.com/azurekid/Piceb)
- **[SIG]** [SigmaXDR: detection conversion](https://github.com/azurekid/SigmaXDR)
- **[DET]** [detection-mcp: detection engineering](https://github.com/azurekid/detection-mcp)
- **[XDR]** [DefenderXDR: security operations automation](https://github.com/azurekid/DefenderXDR)
- **[AH]** [AzureHacking research website](https://azurehacking.com)
- **[AHCHAIN]** [AzureHacking: Azure Tenant Takeover](https://azurehacking.com/post/azure-tenant-takeover-from-exposed-config-to-global-admin)
- **[AHSC]** [AzureHacking: Introducing ScEntra](https://azurehacking.com/post/introducing-scentra-an-advanced-permission-visualizer)
- **[AHESC]** [AzureHacking: Detecting Privilege Escalation in Entra ID](https://azurehacking.com/post/detecting-privilege-escalation-in-entra-id)
- **[AHFIC]** [AzureHacking: Federated Identity Credential Injection](https://azurehacking.com/post/federated-identity-credential-injection-proof-of-concept)
- **[AHKV]** [AzureHacking: Azure Key Vault Security Deep Dive](https://azurehacking.com/post/azure-key-vault-security-deep-dive)
- **[AHCON]** [AzureHacking: Azure API Connections Deep Dive](https://azurehacking.com/post/azure-api-connections-a-red-team-deep-dive)
- **[AHCOP]** [AzureHacking: Copilot Studio Detection & Mitigation](https://azurehacking.com/post/copilot-studio-detection-mitigation)
- **[AHLOG]** [AzureHacking: Diagnostic Setting Manipulation](https://azurehacking.com/post/impairing-azure-defenses-through-diagnostic-setting-manipulation)


## Delivery checklist

- Recheck live article links and current Microsoft feature support.
- Use Presenter View; keep audience slides concise and technical qualifications in notes.
- Rehearse the synthetic demo and keep it fully offline.
- If substituting real assessment evidence, obtain permission and sanitize all identifying data.
- Do not deploy intentionally vulnerable projects or run active tests during the presentation.
- Validate KQL against your own authorized workspace before treating it as a detection rule.
