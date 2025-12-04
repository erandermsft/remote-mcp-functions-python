param name string
@description('Primary location for all resources & Flex Consumption Function App')
param location string = resourceGroup().location
param tags object = {}
param applicationInsightsName string = ''
param appServicePlanId string
param appSettings object = {}
param runtimeName string 
param runtimeVersion string 
param serviceName string = 'api'
param storageAccountName string
param deploymentStorageContainerName string
param virtualNetworkSubnetId string = ''
param instanceMemoryMB int = 2048
param maximumInstanceCount int = 100
param identityId string = ''
param identityClientId string = ''
param enableBlob bool = true
param enableQueue bool = false
param enableTable bool = false
param enableFile bool = false
param subnetResourceId string

@allowed(['SystemAssigned', 'UserAssigned'])
param identityType string = 'UserAssigned'

var applicationInsightsIdentity = 'ClientId=${identityClientId};Authorization=AAD'
var kind = 'functionapp,linux'

// Create base application settings (NameValuePair[])
var baseAppSettings = [
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
  {
    name: 'AzureWebJobsStorage__clientId'
    value: identityClientId
  }
  // Application Insights settings are always included when provided
  // {
  //   name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
  //   value: applicationInsightsIdentity
  // }
  // {
  //   name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
  //   value: applicationInsights?.properties.ConnectionString
  // }
]

// User supplied settings converted to NameValuePair[]
var userAppSettings = [for setting in items(appSettings): {
  name: setting.key
  value: setting.value
}]

// Dynamically build storage endpoint settings based on feature flags
var blobSettings = enableBlob ? [
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: stg.properties.primaryEndpoints.blob
  }
] : []
var queueSettings = enableQueue ? [
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: stg.properties.primaryEndpoints.queue
  }
] : []
var tableSettings = enableTable ? [
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: stg.properties.primaryEndpoints.table
  }
] : []
var fileSettings = enableFile ? [
  {
    name: 'AzureWebJobsStorage__fileServiceUri'
    value: stg.properties.primaryEndpoints.file
  }
] : []

// Merge all app settings arrays
var allAppSettings = concat(
  userAppSettings,
  baseAppSettings,
  blobSettings,
  queueSettings,
  tableSettings,
  fileSettings
)

resource stg 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(applicationInsightsName)) {
  name: applicationInsightsName
}


resource api 'Microsoft.Web/sites@2025-03-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': serviceName })
  kind: kind
  identity: identityType == 'SystemAssigned' ? {
    type: 'SystemAssigned'
  } : {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    outboundVnetRouting: {
      allTraffic: true
    }
    virtualNetworkSubnetId: !empty(virtualNetworkSubnetId) ? virtualNetworkSubnetId : null
    siteConfig: {
      alwaysOn: false
      appSettings: allAppSettings
      
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${stg.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: identityType == 'SystemAssigned' ? 'SystemAssignedIdentity' : 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityType == 'UserAssigned' ? identityId : ''
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: runtimeName
        version: runtimeVersion
      }
    }
  }
}



resource apiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'func-private-endpoint'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'funcPrivateLinkConnection'
        properties: {
          privateLinkServiceId: api.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
    customNetworkInterfaceName: 'func-private-endpoint-nic'
  }
}

output SERVICE_API_NAME string = api.name
output SERVICE_API_IDENTITY_PRINCIPAL_ID string = identityType == 'SystemAssigned' ? api.identity.principalId : ''
output SERVICE_API_RESOURCE_ID string = api.id
