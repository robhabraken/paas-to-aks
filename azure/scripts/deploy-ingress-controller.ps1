param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $AksName
)

# authenticate AKS instance
Write-Host "--- Get credentials for k8s cluster ---" -ForegroundColor Cyan

az aks get-credentials --admin `
    --resource-group $ResourceGroupName `
    --name $AksName `
    --overwrite-existing

Write-Host "--- Creating nginx (Ingress) ---" -ForegroundColor Cyan

# add nginx helm charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm repo update

# update the charts
helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx `
    --set controller.replicaCount=2 `
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux `
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux `
    --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux `
    --set-string controller.config.proxy-body-size=10m `
    --set controller.service.externalTrafficPolicy=Local `
    --wait

Write-Host "--- Ready setting up nginx, now retrieving DNS data... ---" -ForegroundColor Green