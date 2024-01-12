$StartTime = "2023-12-01T00:00:00Z"
$EndTime = "2024-01-07T00:00:00Z"
$TenantId = ""
$ExcludeSouthCentralRegion = $false

$Subscriptions = Get-AzSubscription -TenantId $TenantId

$TotalRequestUnits = 0
$NumberOfDays
$RequestUnitDictionary = @{}

$subscriptions | ForEach-Object {

    $Context = Set-AzContext -SubscriptionId $_.SubscriptionId

    $ResourceGroupsInSubscription = Get-AzResourceGroup

    $ResourceGroupsInSubscription | ForEach-Object {

        $CosmosDBAccounts = Get-AzCosmosDBAccount -ResourceGroupName $_.ResourceGroupName

        $CosmosDBAccounts | ForEach-Object {
            
            if ($ExcludeSouthCentralRegion -eq $true -and $_.Location -eq "South Central US") {
                Write-Output "Excluding Cosmos DB instance $($_.Name) in region $($_.Location)"
                return
            }

            $IndividualCosmosAccountRequestUnits = 0
            $PeakDailyRUConsumption = 0
            $PeakDailyRUDate = "No Date"

            $MetricData = Get-AzMetric -ResourceId $_.Id -MetricName TotalRequestUnits -TimeGrain 01:00:00:00 -StartTime $StartTime -EndTime $EndTime -AggregationType Total -WarningAction SilentlyContinue
            $NumberOfDays = $MetricData.Data.Count
            $MetricData.Data | ForEach-Object {
                $IndividualCosmosAccountRequestUnits += $_.Total
                if ($_.Total -gt $PeakDailyRUConsumption) {
                    $PeakDailyRUConsumption = $_.Total
                    if ($_.TimeStamp -ne $null) {
                        $PeakDailyRUDate = $_.TimeStamp.ToString("yyyy-MM-dd")
                    }
                }
            }

            $IndividualCosmosAccountContext = @{
                TotalRequestUnits = $IndividualCosmosAccountRequestUnits
                # Total Request Units Per Seconds is the total request units consumed divided by the number of days, hours, minutes, and seconds in the time range.
                TotalRequestUnitsPerSecond = $IndividualCosmosAccountRequestUnits / $MetricData.Data.Count / 24 / 60 / 60 
                Region = $_.Location
                PeakDailyRUConsumption = $PeakDailyRUConsumption
                # Peak Daily Request Units Per Seconds is the peak daily request units consumed divided by the number of hours, minutes, and seconds in a day.
                PeakDailyRUPerSecondConsumption = $PeakDailyRUConsumption / 24 / 60 / 60
                PeakDailyRUPerSecondDate = $PeakDailyRUDate
            }

            $RequestUnitDictionary.Add($_.Name, $IndividualCosmosAccountContext)

            $TotalRequestUnits += $IndividualCosmosAccountRequestUnits
        }
    }
}

Write-Output "Total Requests units for all Cosmos DB instances from $StartTime to ${EndTime}: $TotalRequestUnits"

# Total Request Units Per Seconds is the total request units consumed divided by the number of days, hours, minutes, and seconds in the time range.
# This value is for all CosmosDB instances in the subscription.
$TotalRequestUnitsPerSecond = $TotalRequestUnits / 24 / 60 / 60

Write-Output "Total Requests units per second required for all Cosmos DB instances from $StartTime to ${EndTime}: $TotalRequestUnitsPerSecond"

Write-Output "Request Unit context for the last $NumberOfDays days by Cosmos DB instance:"
Write-Output $RequestUnitDictionary | ConvertTo-Json -Depth 4