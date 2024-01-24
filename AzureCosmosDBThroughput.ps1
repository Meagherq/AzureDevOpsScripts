$StartTime = "2023-12-12T00:00:00Z"
$EndTime = "2024-01-12T00:00:00Z"
$TenantId = ""
$ExcludeSouthCentralRegion = $false
$GrowthProjectionMultiplier = 1.15
$InScopeCSV = Import-Csv -Path ./inscopeCosmosTest.csv

$Subscriptions = Get-AzSubscription -TenantId $TenantId
$CSVResult = @()
$TotalRequestUnits = 0
$NumberOfDays = $null
$RequestUnitDictionary = @{}
$TotalPhysicalPartitionSizeContext = 0

$subscriptions | ForEach-Object {
    $SubscriptionId = $_.SubscriptionId
    $Context = Set-AzContext -SubscriptionId $_.SubscriptionId

    $ResourceGroupsInSubscription = Get-AzResourceGroup

    $ResourceGroupsInSubscription | ForEach-Object {

        $CosmosDBAccounts = Get-AzCosmosDBAccount -ResourceGroupName $_.ResourceGroupName
        $ResourceGroupName = $_.ResourceGroupName
        $LocationDictionary = @{}
        $CosmosDBAccounts | ForEach-Object {

            $_.WriteLocations | ForEach-Object {
                $LocationDictionary.Add($_.LocationName, @{ IsZoneRedundant = $_.IsZoneRedundant})
            }
            
            if ($ExcludeSouthCentralRegion -eq $true -and $_.Location -eq "South Central US") {
                Write-Output "Excluding Cosmos DB instance $($_.Name) in region $($_.Location)"
                return
            }
            $IsInScope = $false
            foreach($row in $InScopeCSV) {
                if ($row.Name -eq $_.Name) {
                    $IsInScope = $true
                    # Write-Output "Including Cosmos DB instance $($_.Name) in region $($_.Location)"
                    break
                }
            }
            if ($IsInScope -eq $false) {
                return
            }

            $TotalCosmosDBProvisionedThroughtput = 0
            #$TotalNumberOfPhysicalPartitions = 0
            $IsServerless = $false
            $_.Capabilities | ForEach-Object {
                if ($_.Name -eq "EnableServerless") {
                    $TotalCosmosDBProvisionedThroughtput = "Serverless"
                    $IsServerless = $true
                }
            }
            $AccountName = $_.Name
            if ($IsServerless -eq $false) {
                $Databases = Get-AzCosmosDBSqlDatabase  -ResourceGroupName $ResourceGroupName -AccountName $_.Name
                
                $Databases | ForEach-Object {
                    
                    $DatabaseThroughput = Get-AzCosmosDBSqlDatabaseThroughput -ResourceGroupName $ResourceGroupName -AccountName $AccountName -Name $_.Name

                    if ($DatabaseThroughput.Throughput -ne $null) {
                        $TotalCosmosDBProvisionedThroughtput += $DatabaseThroughput.Throughput
                        #$TotalNumberOfPhysicalPartitions++
                    }
                    else {
                        $Containers = Get-AzCosmosDBSqlContainer -ResourceGroupName $ResourceGroupName -AccountName $AccountName -DatabaseName $_.Name

                        $DatabaseName = $_.Name
        
                        $Containers | ForEach-Object {

                            $ContainerThroughput = Get-AzCosmosDBSqlContainerThroughput -ResourceGroupName $ResourceGroupName -AccountName $AccountName -DatabaseName $DatabaseName -Name $_.Name
                            if ($ContainerThroughput.Throughput -ne $null) {
                                $TotalCosmosDBProvisionedThroughtput += $ContainerThroughput.Throughput
                                #$TotalNumberOfPhysicalPartitions++
                            }
                        }
                    }
                    
                }
            }

            $IndividualCosmosAccountRequestUnits = 0
            $PeakDailyRUConsumption = 0
            $PeakDailyRUDate = "No Date"
            #5 minute time grain for peak daily request units
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

            $PhysicalParititionSize = Get-AzMetric -ResourceId $_.Id -MetricName DataUsage -TimeGrain 01:00:00 -StartTime $StartTime -EndTime $EndTime -AggregationType Max -WarningAction SilentlyContinue
            $TotalPhysicalPartitionSize = 0
            if ($PhysicalParititionSize.Data -ne $null) {
                $TotalPhysicalPartitionSize = $PhysicalParititionSize.Data[$PhysicalParititionSize.Data.Count - 1].Maximum
            }

            $FormattedPhysicalParitionSize = [math]::round($TotalPhysicalPartitionSize / 1Gb, 8)
            #$TotalPhysicalPartitionSizeContext += $FormattedPhysicalParitionSize

            $NumberOfWriteRegionsIncludingZonalMultiplier = $_.WriteLocations.Count * 3
            $GrowthProjectionContext = @{}
            $GrowthProjectionContext.Add("NumberOfWriteRegions", $_.WriteLocations.Count)
            $GrowthProjectionContext.Add("NumberOfWriteRegionsTimesZonalReplications", $_.WriteLocations.Count * 3)
            $physicalParitionGrowthArray = [System.Collections.ArrayList]@()
            $physicalParitionGrowthArrayIncludingRedundancy = [System.Collections.ArrayList]@()
            $iteratedPartitionGrowthIncludingRedundancy = $FormattedPhysicalParitionSize * $NumberOfWriteRegionsIncludingZonalMultiplier
            $physicalParitionGrowthArrayIncludingRedundancy.Add($iteratedPartitionGrowthIncludingRedundancy)
            $iteratedPartitionGrowth = $FormattedPhysicalParitionSize
            $physicalParitionGrowthArray.Add($iteratedPartitionGrowth)
            for ($i = 0; $i -lt 12; $i++)
            {
                $iteratedPartitionGrowthIncludingRedundancy = $iteratedPartitionGrowthIncludingRedundancy * $GrowthProjectionMultiplier
                $physicalParitionGrowthArrayIncludingRedundancy.Add("$iteratedPartitionGrowthIncludingRedundancy GB")
                $iteratedPartitionGrowth = $iteratedPartitionGrowth * $GrowthProjectionMultiplier
                $physicalParitionGrowthArray.Add("$iteratedPartitionGrowth GB")
            }

            $requestUnitGrowthArray = [System.Collections.ArrayList]@()
            $requestUnitGrowthArrayIncludingRedundancy = [System.Collections.ArrayList]@()
            $iteratedRUGrowthIncludingRedundancy = ($IndividualCosmosAccountRequestUnits / $NumberOfDays / 24 / 60 / 60) * $NumberOfWriteRegionsIncludingZonalMultiplier
            $iteratedRUGrowth = $IndividualCosmosAccountRequestUnits / $NumberOfDays / 24 / 60 / 60
            $requestUnitGrowthArrayIncludingRedundancy.Add("$iteratedRUGrowthIncludingRedundancy")
            $requestUnitGrowthArray.Add("$iteratedRUGrowth")
            for ($i = 0; $i -lt 12; $i++)
            {
                $iteratedRUGrowthIncludingRedundancy = $iteratedRUGrowthIncludingRedundancy * $GrowthProjectionMultiplier
                $requestUnitGrowthArrayIncludingRedundancy.Add("$iteratedRUGrowthIncludingRedundancy")
                $iteratedRUGrowth = $iteratedRUGrowth * $GrowthProjectionMultiplier
                $requestUnitGrowthArray.Add("$iteratedRUGrowth")
            }

            if ($IsServerless -eq $false) {
                $provisionedComputeGrowthArrayIncludingRedundancy = [System.Collections.ArrayList]@()
                $iteratedProvisionedComputeGrowthIncludingRedundancy = $TotalCosmosDBProvisionedThroughtput * $NumberOfWriteRegionsIncludingZonalMultiplier
                $provisionedComputeGrowthArray = [System.Collections.ArrayList]@()
                $iteratedProvisionedComputeGrowth = $TotalCosmosDBProvisionedThroughtput
                $provisionedComputeGrowthArrayIncludingRedundancy.Add($iteratedProvisionedComputeGrowthIncludingRedundancy)
                $provisionedComputeGrowthArray.Add($iteratedProvisionedComputeGrowth)
                for ($i = 0; $i -lt 12; $i++)
                {
                    $iteratedProvisionedComputeGrowthIncludingRedundancy = $iteratedProvisionedComputeGrowthIncludingRedundancy * $GrowthProjectionMultiplier
                    $provisionedComputeGrowthArrayIncludingRedundancy.Add($iteratedProvisionedComputeGrowthIncludingRedundancy)
                    $iteratedProvisionedComputeGrowth = $iteratedProvisionedComputeGrowth * $GrowthProjectionMultiplier
                    $provisionedComputeGrowthArray.Add($iteratedProvisionedComputeGrowth)
                }
                $GrowthProjectionContext.Add("MonthlyProvisionedComputeGrowth", $provisionedComputeGrowthArray)
                $GrowthProjectionContext.Add("MonthlyProvisionedComputeGrowthIncludingRedundancy", $provisionedComputeGrowthArrayIncludingRedundancy)
            }
            $GrowthProjectionContext.Add("MonthlyRequestUnitPerSecondGrowth", $requestUnitGrowthArray)
            $GrowthProjectionContext.Add("MonthlyRequestUnitPerSecondGrowthIncludingRedundancy", $requestUnitGrowthArrayIncludingRedundancy)
            
            $GrowthProjectionContext.Add("MonthlyPhysicalPartitionGrowth", $physicalParitionGrowthArray)
            $GrowthProjectionContext.Add("MonthlyPhysicalPartitionGrowthIncludingRedundancy", $physicalParitionGrowthArrayIncludingRedundancy)


            $IndividualCosmosAccountContext = @{
                TotalRequestUnits                   = $IndividualCosmosAccountRequestUnits
                # Total Request Units Per Seconds is the total request units consumed divided by the number of days, hours, minutes, and seconds in the time range.
                TotalRequestUnitsPerSecond          = $IndividualCosmosAccountRequestUnits / $NumberOfDays / 24 / 60 / 60 
                PriaryRegion                        = $_.Location
                PeakDailyRUConsumption              = $PeakDailyRUConsumption
                # Peak Daily Request Units Per Seconds is the peak daily request units consumed divided by the number of hours, minutes, and seconds in a day.
                PeakDailyRUPerSecondConsumption     = $PeakDailyRUConsumption / 24 / 60 / 60
                PeakDailyRUPerSecondDate            = $PeakDailyRUDate
                TotalCosmosDBProvisionedThroughtput = $TotalCosmosDBProvisionedThroughtput
                TotalPhysicalPartitionSize          = "$FormattedPhysicalParitionSize GB"
                #TotalNumberOfPhysicalPartitions     = $TotalNumberOfPhysicalPartitions
                LocationContext                     = $LocationDictionary
                GrowthProjectionContext             = $GrowthProjectionContext
            }
            # $CapacityExport = @{}
            $CapacityExport = [ordered] @{
                SubscriptionId = $SubscriptionId
                AccountName = $_.Name
                Prod = "No"
                "AZ Capacity" = "Y"
                "Brief Description" = ""
                Region = ""
                "Serverless" = $IsServerless
                "Current State - Storage" = $physicalParitionGrowthArray[0]
                "Current State - RU" = If ($IsServerless -eq $true) {$requestUnitGrowthArray[0]} ELSE {$provisionedComputeGrowthArray[0]}
                "Feb 2024 - Storage" = $physicalParitionGrowthArray[1]
                "Feb 2024 - RU" = If ($IsServerless -eq $true) {$requestUnitGrowthArray[1]} ELSE {$provisionedComputeGrowthArray[1]}
                "March 2024 - Storage" = $physicalParitionGrowthArray[2]
                "March 2024 - RU" = If ($IsServerless -eq $true) {$requestUnitGrowthArray[2]} ELSE {$provisionedComputeGrowthArray[2]}
                "April 2024 - Storage" = $physicalParitionGrowthArray[3]
                "April 2024 - RU" = If ($IsServerless -eq $true) {$requestUnitGrowthArray[3]} ELSE {$provisionedComputeGrowthArray[3]}
                "June 2024 - Storage" = $physicalParitionGrowthArray[4]
                "June 2024 - RU" = If ($IsServerless -eq $true) {$requestUnitGrowthArray[4]} ELSE {$provisionedComputeGrowthArray[4]}
            }

            $CSVResult += New-Object PSObject -Property $CapacityExport

            # $CSVResult | Export-Csv -Path ./CosmosDBRequestUnitContext.csv -NoTypeInformation

            $_.WriteLocations | ForEach-Object {
                # $RegionExport = @{}
                $RegionExport = @{
                    Region = $_.LocationName 
                }

                $CSVResult += New-Object PSObject -Property $RegionExport
            }


            $RequestUnitDictionary.Add($_.Name, $IndividualCosmosAccountContext)

            $TotalRequestUnits += $IndividualCosmosAccountRequestUnits
        }
    }
}

Write-Output "Total Requests units for all Cosmos DB instances from $StartTime to ${EndTime}: $TotalRequestUnits"
Write-Output "Total physical partition size for all Cosmos DB instances from $StartTime to ${EndTime}: $TotalPhysicalPartitionSize"

# Total Request Units Per Seconds is the total request units consumed divided by the number of days, hours, minutes, and seconds in the time range.
# This value is for all CosmosDB instances in the subscription.
$TotalRequestUnitsPerSecond = $TotalRequestUnits / $NumberOfDays / 24 / 60 / 60

Write-Output "Total Requests units per second required for all Cosmos DB instances from $StartTime to ${EndTime}: $TotalRequestUnitsPerSecond"

Write-Output "Request Unit context for the last $NumberOfDays days by Cosmos DB instance:"
Write-Output $RequestUnitDictionary | ConvertTo-Json -Depth 6
$CSVResult | Export-Csv -Path ./CosmosDBRequestUnitContext.csv -NoTypeInformation