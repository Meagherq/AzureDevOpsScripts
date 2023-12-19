$MyPat = ''
$organization = ""

$B64Pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("`:$MyPat"))

$projects = Invoke-WebRequest -Uri "https://dev.azure.com/$organization/_apis/projects?api-version=7.0"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

($projects.Content | ConvertFrom-Json).value | ForEach-Object {

    $projectName = $_.name
    $projectId = $_.id

    try {
        $buildPipelineRetention = Invoke-WebRequest -Uri "https://dev.azure.com/$organization/$projectName/_apis/build/retention?api-version=7.0"  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $B64Pat"}
        $testRetention = Invoke-WebRequest -Uri "https://dev.azure.com/$organization/$projectName/_apis/test/resultretentionsettings?api-version=7.0"  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $B64Pat"}
        
        $formattedPipelineRetention = ($buildPipelineRetention.Content | ConvertFrom-Json)
        $formattedOutputTestRetention = ($testRetention.Content | ConvertFrom-Json)

        $formattedResponse = @"
        ------------|Project Name: $projectName|------------------

        Artifact Retention
        ------------------
        Minimum Allowed Days: $($formattedPipelineRetention.purgeArtifacts.min)
        Maximum Allowed Days: $($formattedPipelineRetention.purgeArtifacts.max)
        Current Value: $($formattedPipelineRetention.purgeArtifacts.value)

        Pull Request Retention
        ------------------
        Minimum Allowed Days: $($formattedPipelineRetention.purgePullRequestRuns.min)
        Maximum Allowed Days: $($formattedPipelineRetention.purgePullRequestRuns.max)
        Current Value: $($formattedPipelineRetention.purgePullRequestRuns.value)

        Pipeline Run Retention
        ------------------
        Minimum Allowed Days: $($formattedPipelineRetention.purgeRuns.min)
        Maximum Allowed Days: $($formattedPipelineRetention.purgeRuns.max)
        Current Value: $($formattedPipelineRetention.purgeRuns.value)

        Test Result Retention
        ------------------
        Automated Results Retention in Days: $($formattedOutputTestRetention.automatedResultsRetentionDuration)
        Manual Results Retention in Days: $($formattedOutputTestRetention.manualResultsRetentionDuration)

"@
        Write-Output $formattedResponse
        Write-Output $formattedResponse  | Out-File -FilePath ./output.txt -Append

        #Project Admins
        #Group Entitlements
    } catch {
        
    }

}