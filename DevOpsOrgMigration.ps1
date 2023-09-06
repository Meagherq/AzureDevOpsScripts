#Variables
$targetOrganization="https://dev.azure.com//"
$targetPersonalAccessToken=""
$patUser = ""

# Navigate to URL below. Code in query parameter is used to generate access token.
# https://login.microsoftonline.com/e5ff440d-0854-4245-bcba-baa4251ffcdd/oauth2/v2.0/authorize?client_id=48aff9ec-7d2d-4189-8f21-80f110dad523&response_type=code&redirect_uri=http://localhost:8080/&response_mode=query&scope=https://app.vssps.visualstudio.com/user_impersonation openid profile&state=12345&code_challenge=_beisJXfa3noWpMVAzp0Z1C3YdXCh3Mlm-rAzb37DQk&code_challenge_method=S256

# Parse Excel Values from Disconnected Organizations - TODO: Acquire PATS for source projects; Put into Excel
$CSVOrganizations = Import-Csv -Path ./organizations.csv

# LOOP For-Each list of Organizations #
# Create directory for Source DevOps Organization
foreach ($row in $CSVOrganizations)
{
    
    #$body = @{
    #  grant_type='authorization_code'
    #  client_id='48aff9ec-7d2d-4189-8f21-80f110dad523'
    #  scope='https://app.vssps.visualstudio.com/user_impersonation openid profile'
    #  # Add the authorization code from the query returned from line 6.
    #  code=''
    #  redirect_uri='http://localhost:8080/'
    #  code_verifier='eM98h8_0hdRg9vdu0aBpj6uhfDB2vcNKtnWergcfS9k'
    #}
    #$contentType = 'application/x-www-form-urlencoded'

    # Acquire OAuth token for Azure DevOps
    #$tokenResponse = Invoke-WebRequest -Uri https://login.microsoftonline.com/e5ff440d-0854-4245-bcba-baa4251ffcdd/oauth2/v2.0/token -Method Post -Body $body -ContentType $contentType -Headers @{ Origin='http://localhost'}
    #$jsonTokenResponse = $tokenResponse.Content | ConvertFrom-Json

    $name = $row.Name
    $personalAccessToken = $row.PersonalAccessToken
    $Url = $row.Url
    
    $unencodedBasicAuthString = $patUser + ":" + $personalAccessToken
    $b64EncodedPAT = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($unencodedBasicAuthString))

    # Query for projects within an Organization
    #$projects = Invoke-WebRequest -Uri https://dev.azure.com/$name/_apis/projects?api-version=7.0 -Method Get -ContentType "application-json" -Headers @{"Authorization"="Bearer $jsonTokenResponse.access_token"}
    #$projects = Invoke-WebRequest -Uri https://dev.azure.com/$name/_apis/projects?api-version=7.0  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic "}
    $projects = Invoke-WebRequest -Uri https://dev.azure.com/$name/_apis/projects?api-version=7.0  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $b64EncodedPAT"}

    $organizationDirectory = New-Item -ItemType Directory -Force -Path ./$name

    # INNER LOOP For-Each list of Project in an Organization #
    # Create directory for each Project
    ($projects.Content | ConvertFrom-Json).value | ForEach-Object {

         # Get Current Process to 
         #$projectProcess = Invoke-WebRequest -Uri https://dev.azure.com/$row."Url"/_apis/work/processes/{processTypeId}?api-version=7.0 -Method Get -Headers @{"Authorization"="Bearer $token"}
         
         # Check for ReflectionWorkItemId on Current Process
         #$projectProcess = Invoke-WebRequest -Uri https://dev.azure.com/$row."Url"/_apis/work/processes/$projectProcess.id/workItemTypes/{witRefName}/fields/{fieldRefName}?api-version=7.0 -Method Get -Headers @{"Authorization"="Bearer $token"}
         
         # Import Azure DevOps Repos into Target
         # Query for Repos to ensure once-only migration
         Set-Location -Path ./$name
         New-Item -ItemType Directory -Force -Path $_.name
         # Create new migration configuration in Project directory
         # Skip if already created
         # Navigate to Project specific path 
         Set-Location -Path $_.name

         # Get JSON content from migration configuration
         Copy-Item "../../configuration4.json" -Destination .
         $configurationJson = Get-Content -Path "./configuration4.json" | ConvertFrom-Json
            
         # Script out Organization/Project/PAT details in Source and Destination config objects
         # Prepare as much as possible
         # Update Source for WorkItems
         $configurationJson.Source.Collection = $Url
         $configurationJson.Source.Project = $_.name
         $configurationJson.Source.AuthenticationMode = "AccessToken"
         $configurationJson.Source.PersonalAccessToken = $personalAccessToken

         # Update Destination for WorkItems
         $configurationJson.Target.Collection = $targetOrganization
         $configurationJson.Target.Project = $_.Name
         $configurationJson.Target.AuthenticationMode = "AccessToken"
         $configurationJson.Target.PersonalAccessToken = $targetPersonalAccessToken

         $currentProject = $_

         # Update Endpoints for Pipelines
         $configurationJson.Endpoints.AzureDevOpsEndpoints | ForEach-Object {
            
            if ($_.Name -eq "Source") {
                $_.AccessToken = $personalAccessToken
                $_.Query.Parameters.TeamProject = $currentProject.name
                $_.Organisation = $Name
                $_.Project = $_.name
            }
            if ($_.Name -eq "Target") {
                $_.AccessToken = $targetPersonalAccessToken
                #$_.Query.Parameters.TeamProject = $row.Name
                $_.Organisation = $Name
                $_.Project = $currentProject.name
            }
         }

         $configurationJson | ConvertTo-Json -depth 100 | set-content ./configuration4.json

         # Execute Migration
         try {
             C:\tools\MigrationTools\migration.exe execute --config ./configuration4.json > ./output.txt
         }
         catch {
             #Log Errors with Execution

             Write-Output $Error
             #Write-Output $Error[0].Message
             $Error[0].Message > ./error.txt
         }
         finally {
            #Reset to top level CWD
            Set-Location -Path ../../
         }
    }
}