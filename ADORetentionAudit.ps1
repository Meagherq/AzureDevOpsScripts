$MyPat = ''
$organization = ""

$B64Pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("`:$MyPat"))

$projects = Invoke-WebRequest -Uri "https://dev.azure.com/$organization/_apis/projects?api-version=7.0"  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $B64Pat"}

($projects.Content | ConvertFrom-Json).value | ForEach-Object {

    $projectName = $_.name
    $projectId = $_.id

    try {
        $buildPipelineRetention = Invoke-WebRequest -Uri "https://dev.azure.com/$organization/$projectName/_apis/build/retention?api-version=7.0"  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $B64Pat"}
        
        $formattedOutput = ($buildPipelineRetention.Content | ConvertFrom-Json)

        $formattedResponse = @"
        ------------|Project Name: $projectName|------------------

        Artifact Retention
        ------------------
        Minimum Allowed Days: $($formattedOutput.purgeArtifacts.min)
        Maximum Allowed Days: $($formattedOutput.purgeArtifacts.max)
        Current Value: $($formattedOutput.purgeArtifacts.value)

        Pull Request Retention
        ------------------
        Minimum Allowed Days: $($formattedOutput.purgePullRequestRuns.min)
        Maximum Allowed Days: $($formattedOutput.purgePullRequestRuns.max)
        Current Value: $($formattedOutput.purgePullRequestRuns.value)

        Pipeline Run Retention
        Minimum Allowed Days: $($formattedOutput.purgeRuns.min)
        Maximum Allowed Days: $($formattedOutput.purgeRuns.max)
        Current Value: $($formattedOutput.purgeRuns.value)

"@
        Write-Output $formattedResponse  | Out-File -FilePath ./output.txt -Append
    } catch {
        
    }

}