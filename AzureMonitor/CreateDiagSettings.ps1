Param
(
    [Parameter(Mandatory=$true)]$SubscriptionID,
    [Parameter(Mandatory=$true)]$DiagName
)    
###################################################################
# Author: Adam Orpen                                              #
# Purpose:  Deploy standard diagnostic setting to all resources   #
#           in the named subscription                             #
# Built: 12/3/24                                                  #
# Tested: 12/3/24                                                 #
# Language: Powershell                                            #
# Github: https://github.com/AdamOrpen/AzurePowershellScripts     #
# This script is an idempotent execution intended to be run       #
#     multiple times, depending on the status of your estate.     #
# Please customise following line to set your Workspace target.   #
###################################################################
$WSRID = "/subscriptions/abc/resourceGroups/LAW/providers/Microsoft.OperationalInsights/workspaces/123"
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
    $RID0 = $Resources[0].Id
    $metric = @()
    $log = @()
    $Categories = Get-AzDiagnosticSettingCategory -ResourceId $RID0  
    $categories | ForEach-Object {if($_.CategoryType -eq "Metrics")
        {$metric+=New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name }
        else
        {$log+=New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name }
        }
        foreach ($Resource in $Resources)
        {
            $RID = $Resource.Id
            $RName = $Resource.Name
            $Exists = Get-AzDiagnosticSetting -Name $DiagName -ResourceId $RID -ErrorAction SilentlyContinue
            if ($Exists) {
                write-host "Diagnostic Setting with name $DiagName already exists for $RName. " -ForegroundColor Blue
            }
            else {
                Write-host "Adding Diagnostic setting from Resource called $RName" -ForegroundColor Green
                New-AzDiagnosticSetting -Name $DiagName -ResourceId $RID -WorkspaceId $WSRID -Log $log -Metric $metric
            }
            
        }
}