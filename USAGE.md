# Usage Guide

Follow these steps to provision the Azure resources and deploy the Remote MCP Function App.

## 1. Configure `main.bicepparam`

1. Copy `infra/main.bicepparam.example` to `infra/main.bicepparam`.
2. Update the parameter values:
   - `environmentName`, `location`, `apiServiceName`, `apiUserAssignedIdentityName`, `appServicePlanName`, and `storageAccountName` should match your naming standards.
   - `appSubnetResourceId` must point to an existing subnet that is **delegated to `Microsoft.App/environments`**. This subnet is used for Function App VNet integration.
   - `peSubnetResourceId` must point to the subnet that will host **private endpoints** (no delegations, but it must allow private endpoints and have network policies disabled if required).
   - Leave optional parameters (Application Insights, Log Analytics) empty if you are not bringing existing instances.

A sample parameter file (`infra/main.bicepparam.example`) is provided with comments showing the required resource ID format.

## 2. Deploy Infrastructure

Run the Bicep deployment from the `infra` folder:

```powershell
cd infra
az deployment group create --template-file main.bicep --parameters main.bicepparam --resource-group rg-remote-mcp-functions2
```

Replace the resource group name if you are targeting a different RG.

## 3. Package the Function App

From the `src` directory, build the deployment package using Azure Functions Core Tools:

```powershell
cd ..\src
func pack --output ..\dist\remote-mcp.zip
```

Adjust the output path/name if desired. Ensure you delete or recreate the package whenever the code changes.

## 4. Zip Deploy to the Function App

Use the zip file to deploy to the Function App specified in your parameter file (for example, `func-remote-mcp-python2`). Run this from anywhere:

```powershell
az functionapp deployment source config-zip `
  --resource-group rg-remote-mcp-functions2 `
  --name func-remote-mcp-python2 `
  --src .\dist\remote-mcp.zip
```

Update the `--name` argument if your Function App name differs. After the command succeeds, the MCP server code is live in Azure.

## 5. Next Steps

- Retrieve the MCP extension system key via `az functionapp keys list` or the Azure portal to configure your MCP clients.
- If you enabled VNet integration and private endpoints, verify DNS resolution and firewall rules from your consuming networks.
- Repeat steps 3 and 4 whenever you need to redeploy code changes.
