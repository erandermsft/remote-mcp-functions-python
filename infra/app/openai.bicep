@description('Name of the resource.')
param name string
@description('Location to deploy the resource. Defaults to the location of the resource group.')
param location string = resourceGroup().location
@description('Tags for the resource.')
param tags object = {}
@description('Whether to enable public network access. Defaults to Enabled.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

param subnetResourceId string


var openAIUserRoleDefinitionId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User role ID

param managedIdentityPrincipalId string

//assign openAIUserRoleDefinitionId to umi on OpenAI instance
resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01'   =  {
    name: guid(openAi.id, managedIdentityPrincipalId, openAIUserRoleDefinitionId) // Use managed identity ID
    scope: openAi
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', openAIUserRoleDefinitionId)
      principalId: managedIdentityPrincipalId // Use managed identity ID
      principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
    }
  }

var openAiDeployments = [
  {
    name: 'embedding'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    capacity: 100
  }
]

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: publicNetworkAccess
    disableLocalAuth: true
  }
}

resource openAiDeploymentsResources 'Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview' = [for deployment in openAiDeployments: {
  name: deployment.name
  parent: openAi
  properties: {
    model: deployment.model
  }
  sku: {
    name: 'Standard'
    capacity: deployment.capacity
  }
}]
resource openAiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'openai-private-endpoint'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'openAiPrivateLinkConnection'
        properties: {
          privateLinkServiceId: openAi.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
    customNetworkInterfaceName: 'openai-private-endpoint-nic'
  }
}

@description('ID for the deployed OpenAI resource.')
output id string = openAi.id
@description('Name for the deployed OpenAI resource.')
output name string = openAi.name
@description('Endpoint for the deployed OpenAI resource.')
output endpoint string = openAi.properties.endpoint
@description('Identity principal ID for the deployed OpenAI resource.')
output systemIdentityPrincipalId string = openAi.identity.principalId
