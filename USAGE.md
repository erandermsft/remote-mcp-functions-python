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

From the `src/mcp` directory, build the deployment package using Azure Functions Core Tools:

```powershell
cd ..\src\mcp
func pack --output ..\dist\remote-mcp.zip
```

Adjust the output path/name if desired. Ensure you delete or recreate the package whenever the code changes.

### Working with Multiple Function Apps (e.g., `mcp` and `indexing`)

Each Function App lives in its own subfolder under `src` (for example `src/mcp` and `src/indexing`). Treat each folder as an independent Azure Functions project:

1. **Dependencies** – Place a dedicated `requirements.txt` in every app folder. Install them separately:

  ```powershell
  cd src\mcp
  python -m venv .venv
  .venv\Scripts\activate
  pip install -r requirements.txt
   
  cd ..\indexing
  python -m venv .venv
  .venv\Scripts\activate
  pip install -r requirements.txt
  ```

2. **Local debugging** – Run the Functions host from the specific folder you want to test:

  ```powershell
  cd src\mcp
  func start
   
  cd ..\indexing
  func start
  ```

3. **Packaging/Deployment** – When you need to deploy a given app, run `func pack` (or `func azure functionapp publish`) from that app’s folder so only its files are included in the ZIP.

This structure lets you keep separate dependencies, settings, and deployment pipelines for the MCP server and the indexing Durable Functions app while sharing the same repository.

> **Reminder:** Before running either app locally, update the corresponding `local.settings.json` with your own storage accounts, service endpoints, and secrets. Each folder keeps its own `local.settings.json`, so ensure both are configured.

### Running the Indexing Pipeline Locally

- From `src/indexing`, you can trigger the Durable Functions indexing pipeline via the provided HTTP file:

  ```powershell
  cd src/indexing
  func start
  # in another terminal or VS Code REST client
  code .\run.http
  ```

  Use VS Code’s REST client or `curl` to execute the requests defined in `run.http` after the host starts.
- Double-check that `src/indexing/local.settings.json` contains the correct endpoint URLs, connection strings, and API keys required by the pipeline before invoking the HTTP request.

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
