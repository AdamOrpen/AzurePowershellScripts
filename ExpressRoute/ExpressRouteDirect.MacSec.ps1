Param
(
    [Parameter(Mandatory=$true)][string]$SubscriptionID,
    [Parameter(Mandatory=$false, HelpMessage='Resource Group Name')][string]$ResourceGroupName,
    [Parameter(Mandatory=$true, HelpMessage='Deployment Identifier')][string]$DeploymentName,
    [Parameter(Mandatory=$true, HelpMessage='Azure Region')][string]$Location,
    [Parameter(Mandatory=$true, HelpMessage='Peering Provider')][string]$PeeringLocation,
    [Parameter(Mandatory=$true, HelpMessage='Expressroute Direct Capacity')][ValidateSet('10','40','100')][string]$ERDSpeed,
    [Parameter(Mandatory=$true)][ValidateSet('Dot1Q','QinQ')][string]$Encapsulation,
    [Parameter(Mandatory=$false, HelpMessage='Encryption Key')][string]$CAK
)
###################################################################
#                                                                 #
# Author: Adam Orpen                                              #
# Purpose: Configure ExpressRoute Direct, Encryption and Circuits #
# Built: 17/02/2023                                               #
# Tested: 17/02/2023 (Testers welcome please)                     #
# Language: Powershell                                            #
#                                                                 #
###################################################################


#This script is an idempotent execution intended to be run multiple times, depending on the status of your build. 
#First run will create the Resource Group and the ExpressRoute Direct resource.
#You will then need to generate the LOA and provision the ports. This can take days to complete hence we write the script this way.
#When the ports are provisioned and there is Layer 2 connectivity. You can then enable the MacSec encryption which requires both ends to be connected.
#When MacSec is setup, you can create the ExpressRoute circuits you need as these require the physical ports to be referenced during creation.
#Written by Adam Orpen. 

if (!($ResourceGroupName)) {
    $RGName = "ExpressRouteDirect"
} 
else {
    $RGName = $ResourceGroupName
}
$ERDName = "ERD-" + $DeploymentName
$MIName = "MI-" + $DeploymentName

$subscription = Get-AzSubscription -SubscriptionId $SubscriptionID
set-AzContext -SubscriptionObject $subscription

#First we create the Resource Group 
$ERD = Get-AzResourceGroup -Name $RGName -ErrorAction SilentlyContinue
if (!($ERD)) {
New-AzResourceGroup -Name $RGName -Location $location 
}
else {
    Write-host "Resource Group already created" -ForegroundColor Green
}

#Now we can create the ExpressRoute Direct Resource
$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName -ErrorAction SilentlyContinue
if (!($erDirect)) {
$erDirect = New-AzExpressRoutePort -Name $ERDName -ResourceGroupName $RGName -PeeringLocation $PeeringLocation -BandwidthInGbps $ERDSpeed -Encapsulation $Encapsulation -Location $location 
}
else {
    write-host "Expressroute Direct Resource already created" -ForegroundColor Green
}
#Now we identify the Keyvault to house CKN and CAK
$keyVaults = Get-AzKeyVault -ResourceGroupName $RGName
if (!($KeyVaults)) {
    $Random = Get-Random
    $KVName = "KV-" + $DeploymentName + "-" + $Random
    $KeyVault = New-AzKeyVault -Name $KVName -ResourceGroupName $RGName -Location $Location -SoftDeleteRetentionInDays 30 -ErrorAction Stop
}
else {
    $KeyVault = $Keyvaults[0]
    $KVName = $Keyvault.VaultName 
    write-host "Found $KVName KeyVault. Will use this existing vault" -ForegroundColor Green
    
}
$Identity = Get-AzUserAssignedIdentity -Name $MIName -ResourceGroupName $RGName -ErrorAction SilentlyContinue
if (!($Identity)) {
    $Identity = New-AzUserAssignedIdentity -ResourceGroupName $RGName -Name $MIName -Location $location -ErrorAction Stop
}
else {
    write-host "Managed Identity Resource already created"
}
#CAK and CKN
if (!($CAKInput)) {
    #Thanks to https://numbergenerator.org/random-64-digit-hex-codes-generator for this random Base64 Key as a default
    $CAKInput = "A8410C9E5A491E1FA7CC810777BE4F954E840564D44107500B4A6F286C0A49FF" #64 Bit
    $CAKInput = "D4F652FF303BD9D79412F2331175DFDD" #32 Bit
}

$CKNInput = "1000"
$CAK = ConvertTo-SecureString $CAKInput -AsPlainText -Force
$CKN = ConvertTo-SecureString $CKNInput -AsPlainText -Force
$CAKName = "CAK"
$CKNName = "CKN"

#
#
$MACsecCAKSecret = Get-AzKeyVaultSecret -VaultName $KVName -Name $CAKName
if (!($MACsecCAKSecret)) {
    $MACsecCAKSecret = Set-AzKeyVaultSecret -VaultName $KVName -Name $CAKName -SecretValue $CAK
}
$MACsecCKNSecret = Get-AzKeyVaultSecret -VaultName $KVName -Name $CKNName
if (!($MACsecCKNSecret)) {
    $MACsecCKNSecret = Set-AzKeyVaultSecret -VaultName $KVName -Name $CKNName -SecretValue $CKN
}
Set-AzKeyVaultAccessPolicy -VaultName $KVName -PermissionsToSecrets get -ObjectId $identity.PrincipalId

#Lets reset MacSec to null first
if (!($erDirect)) {
    $erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName
    }
$erDirect.Links[0]. MacSecConfig.CknSecretIdentifier = $null
$erDirect.Links[0]. MacSecConfig.CakSecretIdentifier = $null
$erDirect.Links[1]. MacSecConfig.CknSecretIdentifier = $null
$erDirect.Links[1]. MacSecConfig.CakSecretIdentifier = $null
$erDirect.identity = $null
Set-AzExpressRoutePort -ExpressRoutePort $erDirect
#Now enable the admin state
Set-AzExpressRoutePort -ExpressRoutePort $erDirect
$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName
$erDirect.Links[0].AdminState = "Enabled"
$erDirect.Links[1].AdminState = "Enabled"
Set-AzExpressRoutePort -ExpressRoutePort $erDirect
#Now enable SciState before enabling MacSec
$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName
$erDirect.Links[0].MacSecConfig.SciState = "Enabled"
$erDirect.Links[1].MacSecConfig.SciState = "Enabled"
Set-AzExpressRoutePort -ExpressRoutePort $erDirect

#Now enable MacSec
$erdIdentity = New-AzExpressRoutePortIdentity -UserAssignedIdentityId $identity.Id
$erDirect.identity = $erdIdentity
$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName
$erDirect.Links[0]. MacSecConfig.CknSecretIdentifier = $MacSecCKNSecret.Id
$erDirect.Links[0]. MacSecConfig.CakSecretIdentifier = $MacSecCAKSecret.Id
$erDirect.Links[0]. MacSecConfig.Cipher = "GcmAes256"
$erDirect.Links[1]. MacSecConfig.CknSecretIdentifier = $MacSecCKNSecret.Id
$erDirect.Links[1]. MacSecConfig.CakSecretIdentifier = $MacSecCAKSecret.Id
$erDirect.Links[1]. MacSecConfig.Cipher = "GcmAes256"
$erDirect.identity = $erdIdentity
Set-AzExpressRoutePort -ExpressRoutePort $erDirect
###MacSec Config Reset if required
#$erDirect = Get-AzExpressRoutePort -ResourceGroupName $ERRGName -Name $ERDName
#$erDirect.Links[0]. MacSecConfig.CknSecretIdentifier = $null
#$erDirect.Links[0]. MacSecConfig.CakSecretIdentifier = $null
#$erDirect.Links[1]. MacSecConfig.CknSecretIdentifier = $null
#$erDirect.Links[1]. MacSecConfig.CakSecretIdentifier = $null
#$erDirect.identity = $null
#Set-AzExpressRoutePort -ExpressRoutePort $erDirect

#Now we create the circuits on the ER Direct as required
#The circuits are defined in the CSV file circuits.csv
#Columns in the CSV should be Name,Location,Bandwidth,SKUTier
$ImportFile = Get-ChildItem -Path . -Name Circuits.csv
if (!($ImportFile)) {
    Write-Host "Please create the circuits.csv file and populate it with these columns:"
    Write-Host "Name,Location,Bandwidth,SKUTier"
    write-host "Delimiter should be a comma ,"
}

$CSV = Import-Csv -Delimiter "," -Path .\circuits.csv 
foreach ($ckt in $CSV) {
    $cktName = $ckt.Name
    $cktLocation = $ckt.Location
    $cktBandwidth = $ckt.Bandwidth
    $cktSKUTier = $ckt.SKUTier
    $Circuit = Get-AzExpressRouteCircuit -Name $cktName -ResourceGroupName $RGName -ErrorAction SilentlyContinue
    if (!($Circuit)) {
        New-AzExpressRouteCircuit -Name $cktName -ResourceGroupName $RGName -Location $cktLocation -ExpressRoutePort $erDirect.port -BandwidthInGbps $CktBandwidth -SkuTier $CktSKUTier -Peering $PeeringLocation
    }
}
