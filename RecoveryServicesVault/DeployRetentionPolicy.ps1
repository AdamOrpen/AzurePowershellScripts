Param
(
    [Parameter(Mandatory=$true)][ValidateSet('Test','NonProd','Prod')][string]$State
)
$Company = "Elecosoft"
$StartTime = Get-Date
$Subscriptions = Get-AzSubscription | Sort-Object Name

if ($State -eq "Test")
{
    $Subs = $Subscriptions | Where-Object {$_.Name -eq "YourTestSubscriptionNameHere"}
}
elseif ($State -eq "NonProd") 
{
    $Subs = $Subscriptions | Where-Object {$_.Name -like "*-NonProd*" -or $_.Name -like "*-PreProd*"}
}
elseif ($State -eq "Prod") 
{
    $Subs = $Subscriptions | Where-Object {$_.Name -like "*-Prod*"}
}

[DATETIME]$Time = "18:00"
$Time=$Time.ToUniversalTime()

foreach ($Sub in $Subs)
{
    Set-AzContext -SubscriptionObject $Sub
    $SubName = $Sub.Name
    $RSVs = Get-AzRecoveryServicesVault 
    foreach ($RSV in $RSVs)
    {
        $RSVName = $RSV.Name
        $RSVID = $RSV.ID
        Set-AzRecoveryServicesVaultContext -Vault $RSV
        #Standard Policy
        $StdSchPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
        $StdSchPol.ScheduleRunTimes.Clear()
        $StdSchPol.ScheduleRunTimes.Add($Time)

        $StdRetPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
        $StdRetPol.IsDailyScheduleEnabled=$true
        $StdRetPol.DailySchedule.DurationCountInDays = 30
        $StdRetPol.IsWeeklyScheduleEnabled     = $true
        $StdRetPol.WeeklySchedule.DurationCountInWeeks = 8
        $StdRetPol.IsMonthlyScheduleEnabled    = $true
        $StdRetPol.MonthlySchedule.DurationCountInMonths = 6
        $StdRetPol.IsYearlyScheduleEnabled     = $true
        $StdRetPol.YearlySchedule.DurationCountInYears = 1
        $StdRetPol.YearlySchedule.MonthsOfYear = "December"
        $StdRetPol.YearlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $StdRetPol.YearlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"


        #Minimum Policy
        $MinSchPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
        $MinSchPol.ScheduleRunTimes.Clear()
        $MinSchPol.ScheduleRunTimes.Add($Time)
        $MinRetPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
        $MinRetPol.IsDailyScheduleEnabled=$true
        $MinRetPol.DailySchedule.DurationCountInDays = 8
        $MinRetPol.IsWeeklyScheduleEnabled     = $true
        $MinRetPol.WeeklySchedule.DurationCountInWeeks = 4
        $MinRetPol.IsMonthlyScheduleEnabled    = $true
        $MinRetPol.MonthlySchedule.DurationCountInMonths = 2
        $MinRetPol.IsYearlyScheduleEnabled     = $false

        $StdPolicyName = $Company + "-Standard-VMPolicy"
        $MinPolicyName = $Company + "-Minimum-VMPolicy"
        $StdVMPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $StdPolicyName -ErrorAction SilentlyContinue
        if (!($StdVMPol))
        {
            New-AzRecoveryServicesBackupProtectionPolicy -Name $PolicyName -WorkloadType AzureVM -RetentionPolicy $StdRetPol -SchedulePolicy $StdSchPol -VaultId $RSVID
            Write-Host "New VM Standard Backup policy created for $RSVName in Subscription $SubName"
        }
        else {
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $StdVMPol -RetentionPolicy $StdRetPol -SchedulePolicy $StdSchPol -VaultId $RSVID
            write-host "Existing Standard policy aligned to standard for $RSVName in Subscription $SubName"
        }
        $MinVMPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $MinPolicyName -ErrorAction SilentlyContinue
        if (!($MinVMPol))
        {
            New-AzRecoveryServicesBackupProtectionPolicy -Name $MinPolicyName -WorkloadType AzureVM -RetentionPolicy $MinRetPol -SchedulePolicy $MinSchPol -VaultId $RSVID
            Write-Host "New VM Minimum Backup policy created for $RSVName in Subscription $SubName"
        }
        else {
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $MinVMPol -RetentionPolicy $MinRetPol -SchedulePolicy $MinSchPol -VaultId $RSVID
            write-host "Existing Minimum policy aligned to standard for $RSVName in Subscription $SubName"
        }
    }
}
$EndTime = Get-Date
$RunTime = $EndTime - $StartTime
write-host "Script runtime is $Runtime"