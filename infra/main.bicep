targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''
param containerAppsEnvironmentName string = ''
param containerRegistryName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param webContainerAppName string = ''
param databaseServerName string = ''
param keyVaultName string = ''
param principalId string = ''

@description('The image name for the web service')
param webImageName string = ''

param databaseUsername string = 'remix'
@secure()
param databasePassword string

@secure()
param sessionSecret string

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    dashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

// Container apps host (including container registry)
module containerApps './core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: rg
  params: {
    name: 'app'
    containerAppsEnvironmentName: !empty(containerAppsEnvironmentName) ? containerAppsEnvironmentName : '${abbrs.appManagedEnvironments}${resourceToken}'
    containerRegistryName: !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  }
}

resource keyVaultSecrets 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVaultName
  scope: rg
}

// Web frontend
module web './app/web.bicep' = {
  name: 'web'
  scope: rg
  params: {
    name: !empty(webContainerAppName) ? webContainerAppName : '${abbrs.appContainerApps}web-${resourceToken}'
    location: location
    imageName: webImageName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    keyVaultName: keyVault.outputs.name
    databaseName: postgres.outputs.DATABASE_NAME
    databaseServerHost: postgres.outputs.SERVER_HOST
    databaseUsername: databaseUsername
    databasePassword: keyVaultSecrets.getSecret('databasePassword')
    sessionSecret: keyVaultSecrets.getSecret('sessionSecret')
  }
}

// Postgres setup
module postgres './app/db.bicep' = {
  name: 'postgres'
  scope: rg
  params: {
    administratorLogin: databaseUsername
    administratorLoginPassword: keyVaultSecrets.getSecret('databasePassword')
    location: location
    serverName: !empty(databaseServerName) ? databaseServerName : '${abbrs.dBforPostgreSQLServers}db-${resourceToken}'
    keyVaultName: keyVaultName
  }
}

module keyVault './core/security/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    keyVaultName: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    principalId: principalId
  }
}

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output REACT_APP_WEB_BASE_URL string = web.outputs.SERVICE_WEB_URI
output SERVICE_WEB_NAME string = web.outputs.SERVICE_WEB_NAME
output AZURE_DATABASE_SERVER_NAME string = postgres.outputs.SERVER_NAME
output AZURE_DATABASE_SERVER_HOST string = postgres.outputs.SERVER_HOST
output AZURE_DATABASE_NAME string = postgres.outputs.DATABASE_NAME
output AZURE_DATABASE_USERNAME string = databaseUsername
