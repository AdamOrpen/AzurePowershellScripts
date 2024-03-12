Param
(
    [Parameter(Mandatory=$true)]$SubscriptionID,
    [Parameter(Mandatory=$true)]$DiagName
)    
###################################################################
# Author: Adam Orpen                                              #
# Purpose:  Deploy standardised diagnostic setting to all         #
#           resourcesin the named subscription                    #
# Built: 12/3/24                                                  #
# Tested: 12/3/24                                                 #
# Language: Powershell                                            #
# Github: https://github.com/AdamOrpen/AzurePowershellScripts     #
# This script is an idempotent execution intended to be run       #
#     multiple times, depending on the status of your estate.     #
###################################################################
###################################################################

$Sub = Get-AzSubscription -SubscriptionId $SubscriptionID
Set-AzContext -SubscriptionObject $Sub
$AllResources = Get-AzResource
$RTypes = $AllResources | Sort-Object ResourceType -Unique
$exclusions = @(Get-Content .\exclusions.txt)
$RTypes = $Rtypes |Where-Object {$_.ResourceType -notmatch ($exclusions -Join "|") }
foreach ($RType in $Rtypes)
{
    $RTypeName = $Rtype.ResourceType
    Write-host "Now processing Resource type $RTypeName"
    $Resources = $AllResources | Where-Object {$_.ResourceType -eq $Rtype.ResourceType}
    
        foreach ($Resource in $Resources)
        {
            $RID = $Resource.Id
            $RName = $Resource.Name
            $Diag = Get-AzDiagnosticSetting -ResourceId $RID -Name $DiagName -ErrorAction SilentlyContinue
            if ($Diag)
            {
                Write-host "Removing Diagnostic setting from Resource called $RName" -ForegroundColor Red
                Remove-AzDiagnosticSetting -ResourceId $RID -Name $DiagName
            } 
            
        }
}
