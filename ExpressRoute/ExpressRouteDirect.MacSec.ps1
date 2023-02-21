Param
(
    [Parameter(Mandatory=$true)][string]$SubscriptionID
#    [Parameter(Mandatory=$false, HelpMessage='Resource Group Name')][string]$ResourceGroupName,
#    [Parameter(Mandatory=$true, HelpMessage='Deployment Identifier')][string]$DeploymentName,
#    [Parameter(Mandatory=$true, HelpMessage='Azure Region')][string]$Location,
#    [Parameter(Mandatory=$true, HelpMessage='Peering Provider')][string]$PeeringLocation,
#    [Parameter(Mandatory=$true, HelpMessage='Expressroute Direct Capacity')][ValidateSet('10','40','100')][string]$ERDSpeed,
#    [Parameter(Mandatory=$true)][ValidateSet('Dot1Q','QinQ')][string]$Encapsulation,
#    [Parameter(Mandatory=$false, HelpMessage='Encryption Key')][string]$CAK,
#    [Parameter(Mandatory=$false, HelpMessage='Testing switch')][ValidateSet('True','False')][string]$test
)
###################################################################
#                                                                 #
# Author: Adam Orpen                                              #
# Purpose: Create and Configure ExpressRoute Direct,              #
#     MacSec Encryption and Circuits                              #
# Built: 17/02/2023                                               #
# Tested: 20/02/2023 (Testers with ER Direct welcome please)      #
# Language: Powershell                                            #
# Github: https://github.com/AdamOrpen/AzurePowershellScripts     #
#This script is an idempotent execution intended to be run        #
#     multiple times, depending on the status of your build.      #
#                                                                 #
###################################################################

#$SubscriptionID = ""
$ResourceGroupName = "" 
$DeploymentName = "Static1" # Unique identifier when running multiple tests
$Location = "NorthEurope" # Resource Location
$PeeringLocation = "Equinix-Dublin-DB3" # ER Direct Provider location
$ERDSpeed = "10" # 10,40,100 
$Encapsulation = "Dot1Q" # Dot1Q or QinQ
$CAKInput = ""
$test = "true" # True or False



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
New-AzResourceGroup -Name $RGName -Location $location  -ErrorAction Stop
}
else {
    Write-host "Resource Group already created" -ForegroundColor Green
}

#Now we can create the ExpressRoute Direct Resource
$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName -ErrorAction SilentlyContinue
if (!($erDirect)) {
    $erDirect = New-AzExpressRoutePort -Name $ERDName -ResourceGroupName $RGName -PeeringLocation $PeeringLocation -BandwidthInGbps $ERDSpeed -Encapsulation $Encapsulation -Location $location  -ErrorAction Stop
    #Generate the Letter of Authority
    #New-Item -ItemType Directory -Path "C:\LOA"
    #New-AzExpressRoutePortLOA -ExpressRoutePort $ERDirect -CustomerName TestCustomerName -Destination "C:\LOA" -ErrorAction Stop
}
else {
    write-host "Expressroute Direct Resource already created" -ForegroundColor Green
}

#Now we identify the Keyvault to house CKN and CAK
$keyVaults = Get-AzKeyVault -ResourceGroupName $RGName -ErrorAction SilentlyContinue
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
    write-host "Managed Identity Resource already created" -ForegroundColor Green
}
#CAK and CKN
if (!($CAKInput)) {
    #Thanks to https://numbergenerator.org/random-64-digit-hex-codes-generator for this random Base64 Key as a default
    #$CAKInput = "A8410C9E5A491E1FA7CC810777BE4F954E840564D44107500B4A6F286C0A49FF" #64 Bit
    $CAKInput = "D4F652FF303BD9D79412F2331175DFDD" #32 Bit
}

$CKNInput = "1000"
$SecureCAK = ConvertTo-SecureString $CAKInput -AsPlainText -Force
$SecureCKN = ConvertTo-SecureString $CKNInput -AsPlainText -Force
$CAKName = "CAK"
$CKNName = "CKN"
#
$CAKSecret = Get-AzKeyVaultSecret -VaultName $KVName -Name $CAKName -ErrorAction SilentlyContinue
if (!($CAKSecret)) {
    $CAKSecret = Set-AzKeyVaultSecret -VaultName $KVName -Name $CAKName -SecretValue $SecureCAK -ErrorAction Stop
}
$CKNSecret = Get-AzKeyVaultSecret -VaultName $KVName -Name $CKNName -ErrorAction SilentlyContinue
if (!($CKNSecret)) {
    $CKNSecret = Set-AzKeyVaultSecret -VaultName $KVName -Name $CKNName -SecretValue $SecureCKN -ErrorAction Stop
}
Start-Sleep 10 #Give AZ Graph time to update and present the Managed Identity
Set-AzKeyVaultAccessPolicy -VaultName $KVName -PermissionsToSecrets get -ObjectId $identity.PrincipalId -ErrorAction Stop

#Lets reset MacSec to null first in case we tried already
if (!($erDirect)) {
    $erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName -ErrorAction SilentlyContinue
    }
$erDirect.Links[0]. MacSecConfig.CknSecretIdentifier = $null
$erDirect.Links[0]. MacSecConfig.CakSecretIdentifier = $null
$erDirect.Links[1]. MacSecConfig.CknSecretIdentifier = $null
$erDirect.Links[1]. MacSecConfig.CakSecretIdentifier = $null
$erDirect.identity = $null
Set-AzExpressRoutePort -ExpressRoutePort $erDirect -ErrorAction Stop
#Now enable the admin state
#$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName -ErrorAction SilentlyContinue
$erDirect.Links[0].AdminState = "Enabled"
$erDirect.Links[1].AdminState = "Enabled"
Set-AzExpressRoutePort -ExpressRoutePort $erDirect -ErrorAction Stop
#Now enable SciState before enabling MacSec
#$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName -ErrorAction SilentlyContinue
$erDirect.Links[0].MacSecConfig.SciState = "Enabled"
$erDirect.Links[1].MacSecConfig.SciState = "Enabled"
Set-AzExpressRoutePort -ExpressRoutePort $erDirect -ErrorAction Stop

#Now enable MacSec
$erdIdentity = New-AzExpressRoutePortIdentity -UserAssignedIdentityId $Identity.Id -ErrorAction Stop
$erDirect.identity = $erdIdentity
#$erDirect = Get-AzExpressRoutePort -ResourceGroupName $RGName -Name $ERDName
$erDirect.Links[0]. MacSecConfig.CknSecretIdentifier = $CKNSecret.Id
$erDirect.Links[0]. MacSecConfig.CakSecretIdentifier = $CAKSecret.Id
$erDirect.Links[0]. MacSecConfig.Cipher = "GcmAes256"
$erDirect.Links[1]. MacSecConfig.CknSecretIdentifier = $CKNSecret.Id
$erDirect.Links[1]. MacSecConfig.CakSecretIdentifier = $CAKSecret.Id
$erDirect.Links[1]. MacSecConfig.Cipher = "GcmAes256"
$erDirect.identity = $erdIdentity
Set-AzExpressRoutePort -ExpressRoutePort $erDirect -ErrorAction Stop

#Now we create the circuits on the ER Direct as required
#The circuits are defined in the CSV file circuits.csv
#Columns in the CSV should be Name,Location,Bandwidth,SKUTier,SKUFamily
$ImportFile = Get-ChildItem -Path . -Name Circuits.csv -ErrorAction SilentlyContinue
if (!($ImportFile)) {
    Write-Host "The Circuits.csv file didnt exist so I just created it for you."
    Write-Host "Please populate it with your circuits required and run the script again"
    "Name,Location,Bandwidth,SKUTier,SKUFamily" | Out-File .\Circuits.csv
}
else 
{
    $CSV = Import-Csv -Delimiter "," -Path .\circuits.csv 
    if ($CSV.Count -ne 0) {
        foreach ($ckt in $CSV) {
            $cktName = $ckt.Name
            $cktLocation = $ckt.Location
            $cktBandwidth = $ckt.Bandwidth
            $cktSKUTier = $ckt.SKUTier
            $CktSKUFamily = $ckt.SKUFamily
            $Circuit = Get-AzExpressRouteCircuit -Name $cktName -ResourceGroupName $RGName -ErrorAction SilentlyContinue
            if (!($Circuit)) {
                New-AzExpressRouteCircuit -Name $cktName -ResourceGroupName $RGName -Location $cktLocation -ExpressRoutePort $erDirect -BandwidthInGbps $CktBandwidth -SkuTier  $CktSKUTier -SKUFamily $CktSKUFamily -ErrorAction Stop
            }
        }
    }
    else {
        Write-host "Please populate the Circuits.csv file with at least 1 circuit"
    }
}
if ($Test -eq "True") {
    Write-Host "Build complete. Do you want to remove resources now?"
    Write-host "Any key to continue or Ctrl-C to cancel"
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    Write-Host "Deleting resources now"
    Remove-AzResourceGroup -Name $RGName -Force
}