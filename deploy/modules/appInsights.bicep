@description('The name of the App Insights namespace that will be deployed')
param appInsightsNamespaceName string

@description('The location that we deploy our resources to. Default value is the location of the resource group')
param location string

@description('The Tags to apply to this resource')
param tags object

@description('The Log Analytics Workspace Resource Id to link this App Insights to.')
param logAnalyticsId string

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsNamespaceName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    WorkspaceResourceId: logAnalyticsId
  }
}

output instrumentationKey string = appInsights.properties.InstrumentationKey
