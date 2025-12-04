targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources & Flex Consumption Function App')
@allowed([
  'australiaeast'
  'australiasoutheast'
  'brazilsouth'
  'canadacentral'
  'centralindia'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'eastus2euap'
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'northeurope'
  'norwayeast'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'southindia'
  'spaincentral'
  'swedencentral'
  'uaenorth'
  'uksouth'
  'ukwest'
  'westcentralus'
  'westeurope'
  'westus'
  'westus2'
  'westus3'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string
param vnetEnabled bool = true
param apiServiceName string = ''
param apiUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
param vNetName string
param vNetRGName string
@description('Id of the user identity to be used for testing and debugging. This is not required in production. Leave empty if not needed.')
param principalId string = deployer().objectId
@description('Specifies the name of the subnet for Function App virtual network integration.')
param appSubnetName string
param peSubnetName string
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

resource vnetrg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (vnetEnabled) {
  name: vNetRGName
}

// User assigned managed identity to be used by the function app to reach storage and other dependencies
// Assign specific roles to this identity in the RBAC module
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: ''
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.13'
    storageAccountName: storage.outputs.storageAccountName
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    appSettings: {
    }
    virtualNetworkSubnetId: vnetEnabled ? serviceVirtualNetwork.outputs.appSubnetID : ''
  }
}

// Backing storage for Azure functions backend API
module storage './app/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    location: location
    tags: tags
    storageAccountName: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    containerNames: [
      deploymentStorageContainerName
      'function-releases'  // Container to hold function app deployment packages
      'function-logs'      // Container to hold function app logs if needed
    ]
  }

}

// Define the configuration object locally to pass to the modules
var storageEndpointConfig = {
  enableBlob: true  // Required for AzureWebJobsStorage, .zip deployment, Event Hubs trigger and Timer trigger checkpointing
  enableQueue: true  // Required for Durable Functions and MCP trigger
  enableTable: false  // Required for Durable Functions and OpenAI triggers and bindings
  enableFiles: false   // Not required, used in legacy scenarios
  allowUserIdentityPrincipal: true   // Allow interactive user identity to access for testing and debugging
}

// Consolidated Role Assignments
module rbac 'app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.storageAccountName
    appInsightsName: ''
    //appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    userIdentityPrincipalId: principalId
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    allowUserIdentityPrincipal: storageEndpointConfig.allowUserIdentityPrincipal
  }
}

// Virtual Network & private endpoint to blob storage
module serviceVirtualNetwork 'app/vnet.bicep' =  if (vnetEnabled) {
  name: 'serviceVirtualNetwork'
  scope: vnetrg
  params: {
    location: location
    appSubnetName: appSubnetName
    peSubnetName: peSubnetName
    tags: tags
    vNetName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
  }
}

module storagePrivateEndpoint 'app/storage-PrivateEndpoint.bicep' = if (vnetEnabled) {
  name: 'servicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: vnetEnabled ? serviceVirtualNetwork.outputs.peSubnetName : '' // Keep conditional check for safety, though module won't run if !vnetEnabled
    resourceName: storage.outputs.storageAccountName
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    virtualNetworkResourceGroup: vNetRGName
  }
}

// Monitor application with Azure Monitor - Log Analytics and Application Insights
// module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
//   name: '${uniqueString(deployment().name, location)}-loganalytics'
//   scope: rg
//   params: {
//     name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
//     location: location
//     tags: tags
//     dataRetention: 30
//   }
// }
 
// module monitoring 'br/public:avm/res/insights/component:0.6.0' = {
//   name: '${uniqueString(deployment().name, location)}-appinsights'
//   scope: rg
//   params: {
//     name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
//     location: location
//     tags: tags
//     workspaceResourceId: logAnalytics.outputs.resourceId
//     disableLocalAuth: true
//   }
// }

// App outputs
// output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.connectionString
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_API_NAME string = api.outputs.SERVICE_API_NAME
output AZURE_FUNCTION_NAME string = api.outputs.SERVICE_API_NAME
