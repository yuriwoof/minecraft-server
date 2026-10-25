# Deployment plan

Status: Ready for Validation

## Scope and workspace classification

- Mode: Modify the existing `yuriwoof/minecraft-server` repository.
- Prepare a Minecraft Java Paper server, a Paper plugin starter, and a local plugin development/test environment.
- Prepare repeatable AZD + Bicep infrastructure for Azure Container Apps.
- Explicitly exclude AI/OpenAI features and Forge/Fabric/NeoForge mod development.
- Preparation only: no Azure resources were created, updated, or deployed.

## Existing repository findings

- The existing Compose file ran Spigot 1.20.2 in offline mode, published UDP 19132 and TCP 25565, and contained placeholder startup commands. It is replaced with a loopback-only Paper 26.3 setup, online authentication, whitelist/OP configuration, no RCON, and a Gradle container build profile.
- The existing README referenced Bicep files that were absent from the repository. It now documents the new `infra/` AZD path and identifies the previous VM/Firewall templates as legacy.
- Existing `bicep/mcserver.bicep` allowed shared storage keys and public blob access, used NFS/HNS/SFTP, and hardcoded an operator name. It is retained for history and labeled legacy; the new design is in `infra/main.bicep`.
- Existing `bicep/deploymcvm.bicep` is a separate legacy VM path and is not used by this plan.

## Requirements and architecture decisions

- Workload: small private multiplayer server and local Paper plugin development. Expected initial population is a small group (the server configuration allows up to 10 players); no high availability or automated scaling is required.
- Subscription and region: `labyuohno-spoke` (`09c05b6f-bf39-4584-a2bc-785b3c4b668e`), Japan East (`japaneast`).
- Budget: no monthly budget ceiling was provided. The Azure Retail Pricing query returned no matching entries for the selected `D4` and `Standard_LRS` labels, so this plan does not claim a numeric estimate. Use the Azure Pricing Calculator before provisioning.
- Platform: Paper 26.3 on Java 25; Gradle 9 Kotlin DSL plugin project. Local server and builder are defined in Docker Compose.
- Cloud hosting: Azure Container Apps Workload Profiles, VNet-integrated external environment, `D4` profile with profile count 0–1, one Container App replica maximum, manual start/stop at 0/1, and 120-second termination grace period.
- Public access decision: direct ACA external TCP ingress on 25565 only; no Azure Firewall, custom public IP, UDP, public RCON, or SSH. This was selected to avoid the Firewall cost and topology while preserving the explicitly requested VNet integration.
- Persistence: 100 GiB Standard Azure Files SMB share, mounted at `/data` through a Container Apps environment System Assigned Managed Identity. Storage account shared-key access and public network access are disabled; a Private Endpoint and private DNS zone are included.
- SMB identity authentication is a Microsoft preview feature. The environment identity receives `Storage File Data SMB MI Admin` at storage-account scope. SMB OAuth and Kerberos are enabled; deployment must stop rather than falling back to storage keys if preview support or policy prevents this configuration.
- Access control: Minecraft online authentication and enforced Paper whitelist. Whitelist and operator names are required secure AZD parameters; operators should also be on the whitelist. RCON is disabled and is not exposed.
- Recovery: the share has seven-day soft delete. This is not backup; Azure Backup for Azure Files must be configured and restore-tested separately before production use.
- Observability: Log Analytics with 30-day retention. Cost drivers include active D4 profile time, logs, Azure Files capacity/transactions, Private Endpoint, and network egress. Scale to zero when unused; storage/network/log costs can remain.

## Quota and policy inventory

Read-only quota results previously collected for Japan East:

| Resource/quota | Limit | Usage | Notes |
|---|---:|---:|---|
| ACA ManagedEnvironmentCount | 50 | 0 | Available quota at check time |
| ACA SandboxCores | 20,000 | 0 | Does not validate dedicated D4 profile capacity |
| VirtualNetworks | 1,000 | 1 | Available quota at check time |
| Standard public IP addresses | 1,000 | 2 | No user-managed public IP is added by this design |
| PrivateEndpoints | 65,536 | 0 | Available quota at check time |
| StorageAccounts | 250 | 1 | Available quota at check time |

The current inherited `MCAPSGov Deny Policies` assignment was inspected. Its `Not allowed resource types` parameter blocks classic Compute/Network/Storage resource types; it does not list the new `Microsoft.App`, `Microsoft.Storage`, `Microsoft.Network`, `Microsoft.OperationalInsights`, or role-assignment types used here. Other inherited policies and regional D4 capacity still require re-checking before deployment; policies may change.

## Prepared artifacts

- `plugin/`: Gradle Kotlin DSL project, Paper 26.3 API dependency, Java 25 toolchain, `plugin.yml`, and a minimal `/paperstarter` command.
- `docker-compose.yaml`: Paper server and optional containerized Gradle builder. Local port binding is `127.0.0.1:25565/TCP`; world/plugin data persists under ignored `data/`.
- `azure.yaml`, `infra/main.bicep`, `infra/main.parameters.json`: AZD/Bicep infrastructure, secure parameters, VNet integration, external TCP ingress, Azure Files SMB managed identity, private networking, scale limits, and logs.
- `README.md`, `.env.example`, `.gitignore`: local setup, future AZD environment preparation, scaling runbook, cost drivers, recovery guidance, security boundaries, and ignore rules for environment values and world data.
- The prior `bicep/mcserver.bicep` is annotated as legacy and is not selected for this deployment path.

## Validation results

- `az bicep build --file infra/main.bicep --stdout`: passed. Bicep reports BCP081 for the two ACA `2026-03-02-preview` resource types because the local type registry has no schema for that preview API; all other known properties compile.
- `docker compose --profile tools config --quiet`: passed using temporary process-local sample usernames; no server or build container was started.
- `infra/main.parameters.json` parses as JSON. Docker Compose YAML was parsed by `docker compose config`; `azure.yaml` and `plugin.yml` were parsed with PyYAML.
- Java/Gradle compilation and Paper runtime testing were not available: Java and Gradle are not installed, and the Docker Linux engine is unavailable. No Azure deployment or remote `what-if` was run.

## All validation checks pass

### AZD validation

- [x] 1. AZD installation — `azd version` reports 1.34.1.
- [ ] 2. Schema validation — not run; requires the Azure AZD schema validation tool.
- [ ] 3. Environment setup — no AZD environment was created because only local preparation/validation was authorized.
- [ ] 4. Authentication check — not run as an Azure validation step.
- [ ] 5. Subscription/location check — values are recorded above; no AZD environment was provisioned.
- [x] 6. Aspire pre-provisioning checks — not applicable; this is not an Aspire project.
- [ ] 7. Provision preview — deferred because the user limited this task to local verification.
- [ ] 8. Build verification — Java/Gradle and the Docker Linux engine are unavailable.
- [x] 9. Docker build context validation — no AZD service uses a Dockerfile; the server image is referenced directly and the plugin builder is a local Compose profile.
- [ ] 10. Package validation — not run; it requires an AZD environment and the unavailable Docker engine.
- [x] 11. Azure Policy validation — the read-only inherited resource-type deny list was inspected; it blocks classic Compute/Network/Storage types, not the resource types selected here. Other policies still require a deployment-time review.
- [x] 12. Aspire post-provisioning checks — not applicable; this is not an Aspire project.

### Bicep validation

- [ ] 1. Core validation (CLI, auth, build, validate, what-if) — local build passed, but the Azure `validate` and `what-if` stages were deferred under the local-only verification scope.
- [x] 2. Linting — `az bicep lint` completed; only BCP081 preview-schema warnings remain for the ACA identity/storage API versions.
- [x] 3. Azure Policy validation — see the AZD policy check above; additional policies are a deployment-time gate.

## Validation and deployment gates

1. Run `azure-validate` before any provisioning; specifically validate both ACA preview API versions and required property shapes against the target subscription/region.
2. Confirm dedicated `D4` capacity and profile-count limits in Japan East; the SandboxCores quota is not a substitute for this check.
3. Recheck the latest inherited policies and required permission `Microsoft.Authorization/roleAssignments/write` at the storage-account scope.
4. Confirm ACA environment VNet egress and port 445 reachability to the Storage Private Endpoint, DNS resolution for `privatelink.file.core.windows.net`, role-assignment propagation, and SMB OAuth/Kerberos availability in Japan East.
5. Obtain a budget estimate, configure Azure Backup for Azure Files, and test restore before production.
6. Build the plugin and start the local Paper server when Docker Desktop is available. Validate graceful save/stop behavior locally and in ACA before relying on scale-to-zero.
7. Do not run `azd provision`, `azd up`, or any Azure deployment command as part of this preparation.

## Verified references

- Paper Gradle setup and API coordinate: https://docs.papermc.io/paper/dev/project-setup/
- Paper plugin descriptor: https://docs.papermc.io/paper/dev/plugin-yml/
- itzg Java image tags: https://docker-minecraft-server.readthedocs.io/en/latest/versions/java/
- itzg server properties: https://docker-minecraft-server.readthedocs.io/en/latest/configuration/server-properties/
- ACA Azure Files mounts and SMB managed identity preview: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
- Azure Files managed identities: https://learn.microsoft.com/en-us/azure/storage/files/files-managed-identities
- ACA TCP/external ingress: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
- ACA application lifecycle: https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management
- AZD environment values and Bicep parameter substitution: https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/manage-environment-variables
- Azure Files backup: https://learn.microsoft.com/en-us/azure/backup/azure-file-share-backup-overview
- Azure Pricing Calculator: https://azure.microsoft.com/pricing/calculator/
