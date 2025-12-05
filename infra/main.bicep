targetScope = 'resourceGroup'

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
param storageAccountName string = ''
@description('Id of the user identity to be used for testing and debugging. This is not required in production. Leave empty if not needed.')
param principalId string = deployer().objectId
@description('Specifies the resource ID of the subnet for Function App virtual network integration.')
param appSubnetResourceId string
@description('Specifies the resource ID of the subnet for the Private Endpoint.')
param peSubnetResourceId string
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'


// User assigned managed identity to be used by the function app to reach storage and other dependencies
// Assign specific roles to this identity in the RBAC module
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  // scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
 // scope: rg
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
 // scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: ''
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.13'
    storageAccountName: storage.outputs.storageAccountName
    subnetResourceId: peSubnetResourceId
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    diEndpoint: docintel.outputs.endpoint
    openAIEndpoint: openai.outputs.endpoint
    searchServiceEndpoint: search.outputs.endpoint
    appSettings: {
    }
    virtualNetworkSubnetId: vnetEnabled ? appSubnetResourceId : ''
  }
}

// Backing storage for Azure functions backend API
module storage './app/storage.bicep' = {
  name: 'storage'
//  scope: rg
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
  enableTable: true  // Required for Durable Functions and OpenAI triggers and bindings
  enableFiles: false   // Not required, used in legacy scenarios
  allowUserIdentityPrincipal: true   // Allow interactive user identity to access for testing and debugging
}

// Consolidated Role Assignments
module rbac 'app/rbac.bicep' = {
  name: 'rbacAssignments'
  //scope: rg
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

module storagePrivateEndpoint 'app/storage-PrivateEndpoint.bicep' = if (vnetEnabled) {
  name: 'servicePrivateEndpoint'
 // scope: rg
  params: {
    location: location
    tags: tags
    subnetResourceId: vnetEnabled ?  peSubnetResourceId : '' // Keep conditional check for safety, though module won't run if !vnetEnabled
    resourceName: storage.outputs.storageAccountName
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
  }
}
module openai 'app/openai.bicep' = {
  name: 'openaiDeployment'
 // scope: rg
  params: {
    name: 'openai-${resourceToken}'
    location: location
    tags: tags
    publicNetworkAccess: 'Disabled'
    subnetResourceId: peSubnetResourceId
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
  }
} 
module search 'app/search.bicep' = {
  name: 'searchDeployment'
 // scope: rg
  params: {
    name: 'search-${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'basic'
    }
    disableLocalAuth: true
    openAIName: openai.outputs.name
    pesubnetResourceId: peSubnetResourceId
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
  }
}

module docintel 'app/docintel.bicep' = {
  name: 'docintelDeployment'
 // scope: rg
  params: {
    name: 'docintel-${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'S0'
    }
    //Should probably use separate storage accounts for Functions host and document storage, but this is just an exmaple
    sourceStorageAccountName: storage.outputs.storageAccountName
    publicNetworkAccess: 'Disabled'
    subnetResourceId: peSubnetResourceId
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
  }
}
//This is needed if you want to enable on-demand indexing of new documents from the function app
// module eventgrid 'app/eventgrid.bicep' = {
//   name: 'eventgridSystemTopic'
//  // scope: rg
//   params: {
//     location: location
//     tags: tags
//     storageAccountName: storage.outputs.storageAccountName
//     systemTopicName: 'stg-eventgrid-${resourceToken}'
//   }
// }

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
