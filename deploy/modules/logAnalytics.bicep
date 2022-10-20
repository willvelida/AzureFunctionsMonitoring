@description('The location that we deploy our resources to. Default value is the location of the resource group')
param location string

@description('The name of the Log Analytics workspace to deploy')
param logAnalyticsName string

@description('The Tags to apply to this resource')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
   sku: {
    name: 'PerGB2018'
   }
   publicNetworkAccessForIngestion: 'Enabled'
   publicNetworkAccessForQuery: 'Enabled' 
  }
}

output workspaceId string = logAnalytics.id
