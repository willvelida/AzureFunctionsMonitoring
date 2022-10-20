@description('The name of the App Service Plan that will be deployed')
param appServicePlanName string

@description('The location that we deploy our resources to. Default value is the location of the resource group')
param location string

@description('The Tags to apply to this resource')
param tags object

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'Y1'
  }
  properties: {}
}

output appPlanId string = appServicePlan.id
