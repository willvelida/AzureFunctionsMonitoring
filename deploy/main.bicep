@description('The location that we deploy our resources to. Default value is the location of the resource group')
param location string = resourceGroup().location

@description('The name of our application.')
param applicationName string = uniqueString(resourceGroup().id)

@description('The name of the App Service Plan that will be deployed')
param appServicePlanName string = '${applicationName}-asp'

@description('The name of the Function App that will be deployed')
param functionAppName string = '${applicationName}-func'

@description('The name of the App Insights namespace that will be deployed')
param appInsightsNamespaceName string = '${applicationName}-appins'

@description('The name of the Log Analytics workspace to deploy')
param logAnalyticsName string = '${applicationName}-law'

@description('The name of the Cosmos DB account that will be deployed')
param cosmosDbAccountName string = '${applicationName}-cosmos'

@description('The name of the Service Bus that will be deployed')
param serviceBusName string = '${applicationName}sb'

@description('Name of the storage account provisioned for use by the Function')
param storageAccountName string = take(toLower(replace('${applicationName}func', '-', '')), 24)

param lastDeployed string = utcNow()

var runtime = 'dotnet'
var cosmosDBName = 'OrdersDB'
var cosmosContainerName = 'Orders'
var queueName = 'Orders'
var tags = {
  ApplicationName: 'FunctionAppMonitoring'
  Environment: 'Production'
  LastDeployed: lastDeployed
}
var serviceBusDataReceiverRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions','4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
var serviceBusDataSenderRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions','69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')

module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'law'
  params: {
    location: location 
    logAnalyticsName: logAnalyticsName
    tags: tags
  }
}

module appServicePlan 'modules/appServicePlan.bicep' = {
  name: 'appServicePlan'
  params: {
    appServicePlanName: appServicePlanName 
    location: location
    tags: tags
  }
}

module appInsights 'modules/appInsights.bicep' = {
  name: 'appinsights'
  params: {
    appInsightsNamespaceName: appInsightsNamespaceName
    location: location
    logAnalyticsId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource functionApp 'Microsoft.Web/sites@2020-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.outputs.appPlanId
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.outputs.instrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.outputs.instrumentationKey}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: runtime
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'CosmosDbEndpoint'
          value: cosmosAccount.properties.documentEndpoint
        }
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: serviceBus.properties.serviceBusEndpoint
        }
        {
          name: 'DatabaseName'
          value: cosmosDB.name
        }
        {
          name: 'ContainerName'
          value: cosmosContainer.name
        }
        {
          name: 'ActivityQueueName'
          value: orderQueue.name
        }
      ]
    }
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2021-11-15-preview' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-11-15-preview' = {
  name: cosmosDBName
  parent: cosmosAccount
  properties: {
    resource: {
      id: cosmosDBName
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-11-15-preview' = {
  name: cosmosContainerName
  parent: cosmosDB  
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
    options: {
      autoscaleSettings: {
        maxThroughput: 4000
      }
    }
  }
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: serviceBusName
  tags: tags
  location: location 
  sku: {
    name: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource orderQueue 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = {
  name: queueName
  parent: serviceBus
}

resource serviceBusReceiverRole 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(serviceBus.id, functionApp.id, serviceBusDataReceiverRole)
  scope: serviceBus
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: serviceBusDataReceiverRole
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusSenderRole 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(serviceBus.id, functionApp.id, serviceBusDataSenderRole)
  scope: serviceBus
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: serviceBusDataSenderRole
    principalType: 'ServicePrincipal'
  }
}

module sqlRoleAssignment 'modules/sqlRoleAssignment.bicep' = {
  name: 'sqlRoleAssignment'
  params: {
    cosmosDbAccountName: cosmosAccount.name
    functionAppPrincipalId: functionApp.identity.principalId
  }
}
