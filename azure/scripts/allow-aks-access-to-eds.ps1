<#
    .SYNOPSIS
        Sets inbound rules on Solr and SQL to allow for traffic from AKS cluster.

    .DESCRIPTION
        Using the ARM provisioned External Data Services Solr & SQL, the Kubernetes containers
        are not able to see these EDS from within the AKS cluster by default. This script
        adds an inbound rule to the Network Security Group (NSG) of the Solr Cloud instance
        based on the outbound IP addresses of the AKS cluster, and an inbound VNet rule to
        the VNet of the SQL Server instance coming from the AKS VNet. This utility script,
        together with the provided ARM templates, allows for a fully automated provisioning
        of the External Data Services required by the Sitecore K8s deployment on AKS.

    .PARAMETER ResourceGroupName
        Name of the resource group that holds the AKS cluster and its EDS.

    .NOTES
        Written by Erik Jeroense & Rob Habraken under the MIT License
        Check https://github.com/robhabraken/paas-to-aks for updated versions of this script

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
#>

[CmdletBinding()]
Param (
    # Name of the resource group that holds the AKS cluster and its EDS
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceGroupName
)

# suppress deprecation warnings
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

# gets the outbound IP addresses of the given AKS cluster and adds an inbound rule to the NSG of the Solr Cloud instance
Function Set-NetworkSecurityRuleSolr {
	
	[CmdletBinding()]
	Param (
        [object] $aksCluster,
        [string] $resourceGroup
	)

	Begin {
	}

	Process {

        Write-Host 'Get outbound IPs from AKS cluster'
        
        # retrieve the public IP addresses used for outbound traffic from the AKS cluster
        $publicIPs = Get-AzPublicIpAddress -ResourceGroupName $aksCluster.NodeResourceGroup
        $ipAddresses = $publicIPs.IpAddress

        Write-Host 'Set inbound rule on Solr NSG to allow traffic from AKS cluster'

        # define specifications of rule to set or add
        $nsgRuleName = 'K8s'
        $nsgRuleDescription = 'K8s outbound IPs'
        $nsgRulePriority = 100

        # get the Solr network security group
        [void]($nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like "*solr*" })

        # try to retrieve the rule to set to check if it already exists
        [void]($getRule = $nsg | Get-AzNetworkSecurityRuleConfig -Name $nsgRuleName -errorAction SilentlyContinue)

        # if the rule already exists, update its settings, otherwise add a new rule
        if ($getRule) {

            [void]($nsg | Set-AzNetworkSecurityRuleConfig -Name $nsgRuleName `
                                                          -Description $nsgRuleDescription `
                                                          -Access Allow `
                                                          -Protocol Tcp `
                                                          -Direction Inbound `
                                                          -Priority $nsgRulePriority `
                                                          -SourceAddressPrefix $ipAddresses `
                                                          -SourcePortRange * `
                                                          -DestinationAddressPrefix * `
                                                          -DestinationPortRange *)

        } else {

            [void]($nsg | Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName `
                                                          -Description $nsgRuleDescription `
                                                          -Access Allow `
                                                          -Protocol Tcp `
                                                          -Direction Inbound `
                                                          -Priority $nsgRulePriority `
                                                          -SourceAddressPrefix $ipAddresses `
                                                          -SourcePortRange * `
                                                          -DestinationAddressPrefix * `
                                                          -DestinationPortRange *)

        }

        # update the network security group with the new settings
        [void]($nsg | Set-AzNetworkSecurityGroup)

        Write-Host 'Solr NSG updated with rule to allow inbound AKS traffic'
        Write-Host
	}	
}

# gets the VNet of the given AKS cluster and adds an inbound VNet rule to the VNet of the SQL Server instance
Function Set-VirtualNetworkRuleSql {
	
	[CmdletBinding()]
	Param (
        [object] $aksCluster,
        [string] $resourceGroup
	)

	Begin {
	}

	Process {

        Write-Host 'Get VNet of AKS cluster'

        # get the VNet of the AKS cluster
        [void]($vnet = Get-AzVirtualNetwork -ResourceGroupName $aksCluster.NodeResourceGroup)
        $vnetName = $vnet.name
        $subnet = $vnet.subnets.Where( { $_.name -eq 'aks-subnet' })

        [void]($virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $aksCluster.NodeResourceGroup -Name $vnetName | `
                                 Get-AzVirtualNetworkSubnetConfig -name $subnet.name)

        Write-Host 'Set the Microsoft.Sql endpoint on the AKS subnet'

        # official type name of Microsoft SQL service endpoint
        $serviceEndpoint = 'Microsoft.Sql';

        # get existing service endpoints
        $endpoints = $virtualNetwork.ServiceEndpoints

        # check if the Microsoft SQL endpoint doesn't exist yet
        if (-not ($endpoints.Service -contains $serviceEndpoint)) {

            # add new service endpoint
            Get-AzVirtualNetwork -ResourceGroupName $aksCluster.NodeResourceGroup -Name $vnetName | `
                Set-AzVirtualNetworkSubnetConfig -Name $subnet.name -AddressPrefix $subnet.AddressPrefix -ServiceEndpoint $serviceEndpoint | `
                Set-AzVirtualNetwork
        }

        Write-Host 'Create new VNet rule on SQL to allow inbound traffic from AKS cluster'

        # define VNet rule name
        $vnetRuleName = 'K8s-VNET-Rule'

        # get the SQL server instance from the resource group
        $sqlServer = Get-AzSqlServer -ResourceGroupName $resourceGroup

        # try to retrieve the VNet rule to check if it already exists
        $getVnetRuleObject = Get-AzSqlServerVirtualNetworkRule `
            -ResourceGroupName      $resourceGroup `
            -ServerName             $sqlServer.ServerName `
            -VirtualNetworkRuleName $vnetRuleName `
            -ErrorAction SilentlyContinue;

        # only add if vnet rule for K8s doesn't exist yet
        if (!$getVnetRuleObject) {
        
            New-AzSqlServerVirtualNetworkRule `
                -ResourceGroupName      $resourceGroup `
                -ServerName             $sqlServer.ServerName `
                -VirtualNetworkRuleName $vnetRuleName `
                -VirtualNetworkSubnetId $subnet.Id;
        }
        
        Write-Host 'SQL VNet updated with rule to allow inbound AKS traffic'
        Write-Host
	}	
}

# get the AKS cluster to set the rules for
$aksCluster = Get-AzAksCluster -ResourceGroupName $ResourceGroupName

# set inbound rules on Solr and SQL
Set-NetworkSecurityRuleSolr -aksCluster $aksCluster -resourceGroup $ResourceGroupName
Set-VirtualNetworkRuleSql -aksCluster $aksCluster -resourceGroup $ResourceGroupName
