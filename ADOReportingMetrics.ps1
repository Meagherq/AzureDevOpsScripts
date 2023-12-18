$MyPat = ''


$B64Pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("`:$MyPat"))

$organization = ""
$project = ""
$startdate = "2023-09-01Z"
$areapath = ""
$repo = ""

#Cycle Time
$ct = Invoke-WebRequest -Uri "https://analytics.dev.azure.com/$organization/$project/_odata/v3.0-preview/WorkItems?
        `$filter=WorkItemType eq 'User Story'
            and StateCategory eq 'Completed'
            and CompletedDate ge $startdate
            and startswith(Area/AreaPath,'$areapath')
        &`$select=WorkItemId,Title,WorkItemType,State,Priority,AreaSK
            ,CycleTimeDays,LeadTimeDays,CompletedDateSK
        &`$expand=AssignedTo(`$select=UserName),Iteration(`$select=IterationPath),Area(`$select=AreaPath)
        &`$apply=aggregate(LeadTimeDays with average as AverageLeadTimeInDays)"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

Write-Output ($ct.Content | ConvertFrom-Json).value

#Cycle Time
$ct = Invoke-WebRequest -Uri "https://analytics.dev.azure.com/$organization/$project/_odata/v3.0-preview/WorkItems?
        `$filter=WorkItemType eq 'User Story'
            and StateCategory eq 'Completed'
            and CompletedDate ge $startdate
            and startswith(Area/AreaPath,'$areapath')
        &`$select=WorkItemId,Title,WorkItemType,State,Priority,AreaSK
            ,CycleTimeDays,LeadTimeDays,CompletedDateSK
        &`$expand=AssignedTo(`$select=UserName),Iteration(`$select=IterationPath),Area(`$select=AreaPath)
        &`$apply=aggregate(CycleTimeDays with average as AverageCycleTimeInDays)"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

Write-Output ($ct.Content | ConvertFrom-Json).value


#Deployment Frequency
$df = Invoke-WebRequest -Uri "https://analytics.dev.azure.com/$organization/$project/_odata/v3.0-preview/PipelineRuns?%20
`$apply=filter(
	CompletedDate ge $startdate
	)
/groupby(
(Pipeline/PipelineName), 
aggregate(
	`$count as TotalCount,
	SucceededCount with sum as SucceededCount,
	FailedCount with sum as FailedCount,
	PartiallySucceededCount with sum as PartiallySucceededCount,
	CanceledCount with sum as CanceledCount
))
"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

Write-Output ($df.Content | ConvertFrom-Json).value

# Pull Requests

$pullRequests = Invoke-WebRequest -Uri "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repo/pullRequests?api-version=5.0&`$top=100&`$skip=0"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

Write-Output ($pullRequests.Content | ConvertFrom-Json).value

#Open Work Items
$openWorkItems = Invoke-WebRequest -Uri "https://analytics.dev.azure.com/$organization/$project/_odata/v3.0-preview/WorkItems?
        `$filter=WorkItemType eq 'User Story'
            and StateCategory ne 'Completed'
            and startswith(Area/AreaPath,'$areapath')
        &`$select=WorkItemId,Title,WorkItemType,State,Priority,AreaSK
            ,CycleTimeDays,LeadTimeDays,CompletedDateSK
        &`$expand=AssignedTo(`$select=UserName),Iteration(`$select=IterationPath),Area(`$select=AreaPath)"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

Write-Output ($openWorkItems.Content | ConvertFrom-Json).value