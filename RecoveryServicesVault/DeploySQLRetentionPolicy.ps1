Param
(
    [Parameter(Mandatory=$true)][ValidateSet('Test','NonProd','Prod')][string]$State
)
###################################################################
# Author: Adam Orpen                                              #
# Purpose: Deploy standardised retention policies to all          #
#     Recovery Services Vaults in a range of subscriptions        #
# Built: 17/02/2023                                               #
# Tested: 20/02/2023                                              #
# Language: Powershell                                            #
# Github: https://github.com/AdamOrpen/AzurePowershellScripts     #
# This script is an idempotent execution intended to be run       #
#     multiple times, depending on the status of your estate.     #
# Please customise lines 18 and 25 to                             #
#    set your company name and test estate                        #
###################################################################
$Company = "ABC123"
$TestSubscriptionName = "TestSub"
###################################################################

$StartTime = Get-Date
$Subscriptions = Get-AzSubscription | Sort-Object Name

if ($State -eq "Test")
{
    $Subs = $Subscriptions | Where-Object {$_.Name -eq $TestSubscriptionName}
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
        $StdFullSQLPol = ""
        $StdDiffSQLPol = ""
        $MinFullSQLPol = ""
        $MinDiffSQLPol = ""
        $RSVName = $RSV.Name
        $RSVID = $RSV.ID
        Set-AzRecoveryServicesVaultContext -Vault $RSV

        #Standard Full Policy
        $StdFullSchPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "MSSQL"
        $StdFullSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Clear()
        $StdFullSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Add($Time)
        $StdFullSchPol.FullBackupSchedulePolicy.ScheduleRunFrequency = "Daily"

        $StdFullSchPol.LogBackupSchedulePolicy.ScheduleFrequencyInMins = 15

        $StdFullRetPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "MSSQL"
        $StdFullRetPol.FullBackupRetentionPolicy.IsDailyScheduleEnabled = $true
        $StdFullRetPol.FullBackupRetentionPolicy.DailySchedule.DurationCountInDays = 30

        $StdFullRetPol.FullBackupRetentionPolicy.IsWeeklyScheduleEnabled = $true
        $StdFullRetPol.FullBackupRetentionPolicy.WeeklySchedule.DurationCountInWeeks = 8
        $StdFullRetPol.FullBackupRetentionPolicy.WeeklySchedule.DaysOfTheWeek = "Friday"

        $StdFullRetPol.FullBackupRetentionPolicy.IsMonthlyScheduleEnabled = $true
        $StdFullRetPol.FullBackupRetentionPolicy.MonthlySchedule.DurationCountInMonths = 6
        $StdFullRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $StdFullRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"

        $StdFullRetPol.FullBackupRetentionPolicy.IsYearlyScheduleEnabled = $true
        $StdFullRetPol.FullBackupRetentionPolicy.YearlySchedule.DurationCountInYears = 1
        $StdFullRetPol.FullBackupRetentionPolicy.YearlySchedule.MonthsOfYear = "December"
        $StdFullRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $StdFullRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"
        $StdFullSQLPolName = $Company + "-Standard-Full-SQLPolicy"
        $StdFullSQLPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $StdFullSQLPolName -ErrorAction SilentlyContinue
        if (!($StdFullSQLPol))
        {
            New-AzRecoveryServicesBackupProtectionPolicy -Name $StdFullSQLPolName -WorkloadType MSSQL -RetentionPolicy $StdFullRetPol -SchedulePolicy $StdFullSchPol -VaultId $RSVID
            Write-Host "New Standard Full SQL Backup policy created for $RSVName in Subscription $SubName"
        }
        else {
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $StdFullSQLPol -RetentionPolicy $StdFullRetPol -SchedulePolicy $StdFullSchPol -VaultId $RSVID
            write-host "Existing Standard Full policy aligned to standard for $RSVName in Subscription $SubName"
        }

        #Standard Differential Policy
        $StdDiffSchPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "MSSQL"
        $StdDiffSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Clear()
        $StdDiffSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Add($Time)
        $StdDiffSchPol.FullBackupSchedulePolicy.ScheduleRunFrequency = "Weekly"
        $StdDiffSchPol.FullBackupSchedulePolicy.ScheduleRunDays = "Friday"

        $StdDiffSchPol.IsDifferentialBackupEnabled = $true
        $StdDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunTimes.Clear()
        $StdDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunTimes.Add($Time)
        $StdDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunFrequency = "Weekly"
        $StdDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunDays = "Saturday","Sunday","Monday","Tuesday","Wednesday","Thursday"

        $StdDiffSchPol.LogBackupSchedulePolicy.ScheduleFrequencyInMins = 15

        $StdDiffRetPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "MSSQL"
        $StdDiffRetPol.FullBackupRetentionPolicy.IsDailyScheduleEnabled = $false

        $StdDiffRetPol.FullBackupRetentionPolicy.IsWeeklyScheduleEnabled = $true
        $StdDiffRetPol.FullBackupRetentionPolicy.WeeklySchedule.DurationCountInWeeks = 8
        $StdDiffRetPol.FullBackupRetentionPolicy.WeeklySchedule.DaysOfTheWeek = "Friday"

        $StdDiffRetPol.FullBackupRetentionPolicy.IsMonthlyScheduleEnabled = $true
        $StdDiffRetPol.FullBackupRetentionPolicy.MonthlySchedule.DurationCountInMonths = 6
        $StdDiffRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $StdDiffRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"

        $StdDiffRetPol.FullBackupRetentionPolicy.IsYearlyScheduleEnabled = $true
        $StdDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.DurationCountInYears = 1
        $StdDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.MonthsOfYear = "December"
        $StdDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $StdDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"

        $StdDiffRetPol.DifferentialBackupRetentionPolicy.RetentionCount = 30

        $StdDiffRetPol.LogBackupRetentionPolicy.RetentionCount = 15

        $StdDiffSQLPolName = $Company + "-Standard-Diff-SQLPolicy"
        $StdDiffSQLPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $StdDiffSQLPolName -ErrorAction SilentlyContinue
        if (!($StdDiffSQLPol))
        {
            New-AzRecoveryServicesBackupProtectionPolicy -Name $StdDiffSQLPolName -WorkloadType MSSQL -RetentionPolicy $StdDiffRetPol -SchedulePolicy $StdDiffSchPol -VaultId $RSVID
            Write-Host "New Standard Differential SQL Backup policy created for $RSVName in Subscription $SubName"
        }
        else {
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $StdDiffSQLPol -RetentionPolicy $StdDiffRetPol -SchedulePolicy $StdDiffSchPol -VaultId $RSVID
            write-host "Existing Standard Differential policy aligned to standard for $RSVName in Subscription $SubName"
        }

        #Minimum Full Policy
        $MinFullSchPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "MSSQL"
        $MinFullSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Clear()
        $MinFullSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Add($Time)
        $MinFullSchPol.FullBackupSchedulePolicy.ScheduleRunFrequency = "Daily"
        $MinFullSchPol.LogBackupSchedulePolicy.ScheduleFrequencyInMins = 15

        $MinFullRetPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "MSSQL"
        $MinFullRetPol.FullBackupRetentionPolicy.IsDailyScheduleEnabled = $true
        $MinFullRetPol.FullBackupRetentionPolicy.DailySchedule.DurationCountInDays = 8

        $MinFullRetPol.FullBackupRetentionPolicy.IsWeeklyScheduleEnabled = $true
        $MinFullRetPol.FullBackupRetentionPolicy.WeeklySchedule.DurationCountInWeeks = 5
        $MinFullRetPol.FullBackupRetentionPolicy.WeeklySchedule.DaysOfTheWeek = "Friday"

        $MinFullRetPol.FullBackupRetentionPolicy.IsMonthlyScheduleEnabled = $true
        $MinFullRetPol.FullBackupRetentionPolicy.MonthlySchedule.DurationCountInMonths = 2
        $MinFullRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $MinFullRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"

        $MinFullRetPol.LogBackupRetentionPolicy.RetentionCount = 8
        $MinFullRetPol.FullBackupRetentionPolicy.IsYearlyScheduleEnabled = $false
        #$MinFullRetPol.FullBackupRetentionPolicy.YearlySchedule.DurationCountInYears = 1
        #$MinFullRetPol.FullBackupRetentionPolicy.YearlySchedule.MonthsOfYear = "December"
        #$MinFullRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        #$MinFullRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"
        $MinFullSQLPolName = $Company + "-Minimum-Full-SQLPolicy"
        $MinFullSQLPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $MinFullSQLPolName -ErrorAction SilentlyContinue
        if (!($MinFullSQLPol))
        {
            New-AzRecoveryServicesBackupProtectionPolicy -Name $MinFullSQLPolName -WorkloadType MSSQL -RetentionPolicy $MinFullRetPol -SchedulePolicy $MinFullSchPol -VaultId $RSVID
            Write-Host "New Minimum Full SQL Backup policy created for $RSVName in Subscription $SubName"
        }
        else {
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $MinFullSQLPol -RetentionPolicy $MinFullRetPol -SchedulePolicy $MinFullSchPol -VaultId $RSVID
            write-host "Existing Minimum Full policy aligned to standard for $RSVName in Subscription $SubName"
        }

        #Minimum Differential Policy
        $MinDiffSchPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "MSSQL"
        $MinDiffSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Clear()
        $MinDiffSchPol.FullBackupSchedulePolicy.ScheduleRunTimes.Add($Time)
        $MinDiffSchPol.FullBackupSchedulePolicy.ScheduleRunFrequency = "Weekly"
        $MinDiffSchPol.FullBackupSchedulePolicy.ScheduleRunDays = "Friday"

        $MinDiffSchPol.IsDifferentialBackupEnabled = $true
        $MinDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunTimes.Clear()
        $MinDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunTimes.Add($Time)
        $MinDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunFrequency = "Weekly"
        $MinDiffSchPol.DifferentialBackupSchedulePolicy.ScheduleRunDays = "Saturday","Sunday","Monday","Tuesday","Wednesday","Thursday"

        $MinDiffSchPol.LogBackupSchedulePolicy.ScheduleFrequencyInMins = 15

        $MinDiffRetPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "MSSQL"
        $MinDiffRetPol.FullBackupRetentionPolicy.IsDailyScheduleEnabled = $false

        $MinDiffRetPol.FullBackupRetentionPolicy.IsWeeklyScheduleEnabled = $true
        $MinDiffRetPol.FullBackupRetentionPolicy.WeeklySchedule.DurationCountInWeeks = 5
        $MinDiffRetPol.FullBackupRetentionPolicy.WeeklySchedule.DaysOfTheWeek = "Friday"

        $MinDiffRetPol.FullBackupRetentionPolicy.IsMonthlyScheduleEnabled = $true
        $MinDiffRetPol.FullBackupRetentionPolicy.MonthlySchedule.DurationCountInMonths = 2
        $MinDiffRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        $MinDiffRetPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"

        $MinDiffRetPol.FullBackupRetentionPolicy.IsYearlyScheduleEnabled = $false
        #$MinDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.DurationCountInYears = 1
        #$MinDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.MonthsOfYear = "December"
        #$MinDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = "Friday"
        #$MinDiffRetPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = "Last"

        $MinDiffRetPol.DifferentialBackupRetentionPolicy.RetentionCount = 8
        $MinDiffRetPol.LogBackupRetentionPolicy.RetentionCount = 8
        $MinDiffSQLPolName = $Company + "-Minimum-Diff-SQLPolicy"
        $MinDiffSQLPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $MinDiffSQLPolName -ErrorAction SilentlyContinue
        if (!($MinDiffSQLPol))
        {
            New-AzRecoveryServicesBackupProtectionPolicy -Name $MinDiffSQLPolName -WorkloadType MSSQL -RetentionPolicy $MinDiffRetPol -SchedulePolicy $MinDiffSchPol -VaultId $RSVID
            Write-Host "New Minimum Differential SQL Backup policy created for $RSVName in Subscription $SubName"
        }
        else {
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $MinDiffSQLPol -RetentionPolicy $MinDiffRetPol -SchedulePolicy $MinDiffSchPol -VaultId $RSVID
            write-host "Existing Minimum Differential policy aligned to standard for $RSVName in Subscription $SubName"
        }
    }
    
}

$EndTime = Get-Date
$RunTime = $EndTime - $StartTime
write-host "Script runtime is $Runtime"