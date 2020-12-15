# PaaS to AKS

Boilerplate project for deploying Sitecore 10.0 or 10.0 Update-1 to Azure Kubernetes Service (AKS) coming from an Azure PaaS architecture for Sitecore. 

Among other things, this boilerplate contains:
* Updated and tested scripts to support a full Infrastructure-as-Code setup for Sitecore on AKS
* Preparation (in combination with Azure DevOps configuration) to move secrets over to an Azure KeyVault instance to prevent storing secrets in the code repository
* ARM templates for External Data Services, required to run Sitecore k8s in production

We are still working on:
* A full YAML based pipeline(s) for releasing custom Sitecore projects to the AKS cluster

For more information, read the accompanying blog posts at https://www.robhabraken.nl/index.php/3582/from-sitecore-paas-to-aks-a-series/