# Copilot Instructions

## Guidelines for Creating Secure Resources in Microsoft Azure

To ensure that resources created in Microsoft Azure comply with the Microsoft Security Benchmark, follow these guidelines:

### Use Role-Based Access Control (RBAC)

RBAC should always be used to manage access to resources. This ensures that only authorized users have access to specific resources, reducing the risk of unauthorized access.

### Avoid Public Endpoints

Resources should never have public endpoints. Instead, use private endpoints or virtual network service endpoints to restrict access to resources. This helps to prevent unauthorized access and potential security breaches.

### Key Vault Security

To ensure the security of Key Vaults, follow these guidelines based on the Microsoft Security Benchmark:

- **Use Private Endpoints**: Ensure that your Key Vaults are not accessible over the public internet by using private endpoints.
- **Enable Soft Delete and Purge Protection**: Enable soft delete and purge protection to protect your keys, secrets, and certificates from accidental or malicious deletion.
- **Use RBAC for Access Control**: Use Azure RBAC to control access to your Key Vaults. Assign the appropriate roles to users and applications to ensure that only authorized entities can access your Key Vaults.
- **Enable Logging and Monitoring**: Enable logging and monitoring for your Key Vaults to track access and usage. Use Azure Monitor and Azure Security Center to monitor and analyze the logs for any suspicious activities.
- **Use Managed Identities**: Use managed identities for Azure resources to access your Key Vaults. This eliminates the need to manage credentials and reduces the risk of credential exposure.
