metadata description = 'Creates an Azure AI Search instance.'
param name string
param location string = resourceGroup().location
param tags object = {}
param openAIName string

param sku object = {
  name: 'basic'
}

param disableLocalAuth bool = true
param encryptionWithCmk object = {
  enforcement: 'Unspecified'
}
@allowed([
  'default'
  'highDensity'
])
param hostingMode string = 'default'
param partitionCount int = 1
param replicaCount int = 1
@allowed([
  'disabled'
  'free'
  'standard'
])
param semanticSearch string = 'free'
param pesubnetResourceId string
param managedIdentityPrincipalId string


var aiSearchIndexerRoleDefinitionId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // Cognitive Search Index Data Contributor role ID
var aiSearchContributorRoleDefinitionId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
//assign aiSearchIndexerRoleDefinitionId to umi on AI Search instance
resource searchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =  {
  name: guid(search.id, managedIdentityPrincipalId, aiSearchIndexerRoleDefinitionId) // Use managed identity ID
  scope: search
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', aiSearchIndexerRoleDefinitionId)
    principalId: managedIdentityPrincipalId // Use managed identity ID
    principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
  }
}
resource searchContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =  {
  name: guid(search.id, managedIdentityPrincipalId, aiSearchContributorRoleDefinitionId) // Use managed identity ID
  scope: search
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', aiSearchContributorRoleDefinitionId)
    principalId: managedIdentityPrincipalId // Use managed identity ID
    principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
  }
}



resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: name
  location: location
  tags: tags
  // The free tier does not support managed identity
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: disableLocalAuth
    encryptionWithCmk: encryptionWithCmk
    hostingMode: hostingMode
    partitionCount: partitionCount
    publicNetworkAccess: 'disabled'
    replicaCount: replicaCount
    semanticSearch: semanticSearch
  }
  sku: sku
}

resource openAI 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = {
  name: openAIName
}

resource cognitiveServicesOAIUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(openAI.id, search.id, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAI
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
resource searchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'search-private-endpoint'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: pesubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'searchPrivateLinkConnection'
        properties: {
          privateLinkServiceId: search.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
    customNetworkInterfaceName: 'search-private-endpoint-nic'
  }
}
output id string = search.id
output endpoint string = 'https://${name}.search.windows.net/'
output name string = search.name
output principalId string = search.identity.principalId 
