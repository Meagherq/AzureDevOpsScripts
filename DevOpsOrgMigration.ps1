#Variables
$targetOrganization="https://dev.azure.com//"
$organizationName=""
$targetPersonalAccessToken=""
$targetPatUser = ""
$sourcePersonalAccessToken=""
$sourcePatUser = ""
$templateId = ""

# Parse Excel Values from Disconnected Organizations - TODO: Acquire PATS for source projects; Put into Excel
$CSVOrganizations = Import-Csv -Path ./organizations.csv

# LOOP For-Each list of Organizations #
# Create directory for Source DevOps Organization
foreach ($row in $CSVOrganizations)
{
    $name = $row.Name
    $Url = $row.Url
    
    $b64EncodedPATTarget = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($targetPatUser + ":" + $targetPersonalAccessToken))
    $b64EncodedPATSource = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sourcePatUser + ":" + $sourcePersonalAccessToken))
    Write-Output $b64EncodedPATTarget
    Write-Output $b64EncodedPATSource
    
    # Query for projects within an Organization
    $projects = Invoke-WebRequest -Uri https://dev.azure.com/$name/_apis/projects?api-version=7.0  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $b64EncodedPATSource"}
    $organizationDirectory = New-Item -ItemType Directory -Force -Path ./$name

    # For-Each list of Project in an Organization #
    # Create directory for each Project
    ($projects.Content | ConvertFrom-Json).value | ForEach-Object {

         $sourceProjectName = $_.name

         Write-Output $sourceProjectName

         # Check if project exists in the target directory
         $existingProject = @{}
         try {
            $existingProject = Invoke-WebRequest -Uri https://dev.azure.com/MigrationDestinationQRM/_apis/projects/"$sourceProjectName"?api-version=7.0  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
         }
         catch { 
         
            if (($_[0] | ConvertFrom-Json).typeName -eq "Microsoft.TeamFoundation.Core.WebApi.ProjectDoesNotExistWithNameException, Microsoft.TeamFoundation.Core.WebApi") 
            {

                $projectParameters = @{
                    name             = $sourceProjectName
                    description      = 'Test'
                    capabilities     = @{
                        processTemplate        = @{
                            templateTypeId     = $templateId
                        }
                    }
                }
            #Create Project in Destination Organization
            $existingProject = Invoke-WebRequest -Uri https://dev.azure.com/MigrationDestinationQRM/_apis/projects/"$sourceProjectName"?api-version=7.0  -Method Post -Body ($projectParameters | ConvertTo-Json) -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
            }
         }

        # Migrate Repos from Source
        $sourceRepos = Invoke-WebRequest -Uri https://dev.azure.com/$name/$sourceProjectName/_apis/git/repositories?api-version=7.1-preview.1  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATSource"}
        ($sourceRepos.Content | ConvertFrom-Json).value | ForEach-Object { 

            $sourceRepo = $_
            #Check if repo existing in target project
            $sourceRepositoryId = $_.id
            $existingRepo = @{}
            try {
                $existingRepo = Invoke-WebRequest -Uri https://dev.azure.com/MigrationDestinationQRM/$sourceProjectName/_apis/git/repositories/"$sourceRepositoryId"?api-version=7.1-preview.1  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
                Write-Output $existingRepo
                break
            }
            catch {
                if (($_[0] | ConvertFrom-Json).typeName -eq "Microsoft.TeamFoundation.Git.Server.GitRepositoryNotFoundException, Microsoft.TeamFoundation.Git.Server") 
                {
                    
                    $existingProject = $existingProject.Content | ConvertFrom-Json

                    Write-Output $existingProject
                    $newRepoParameters = @{
                        name        = $sourceRepo.name
                        project     = @{
                            id        = $existingProject.id
                        }
                    }

                    $newRepo = Invoke-WebRequest -Uri https://dev.azure.com/MigrationDestinationQRM/$sourceProjectName/_apis/git/repositories?api-version=7.0  -Method Post -ContentType "application/json" -Body ($newRepoParameters | ConvertTo-Json) -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
                    
                    $newRepo = $newRepo.Content | ConvertFrom-Json

                    #Will need to source templateId manually.
                    $repoImportParameters = @{

                        parameters     = @{

                            deleteServiceEndpointAfterImportIsDone = false
                            gitSource        = @{
                                url     = $sourceRepo.remoteUrl
                            }
                            tfvcSource                             = "test"
                            serviceEndpointId                      = "test"
                        }

                    }

                    $newRepoId = $newRepo.id

                    #Hitting 400 Bad Request with no message
                    $newImportedRepo = Invoke-WebRequest -Uri https://dev.azure.com/MigrationDestinationQRM/$sourceProjectName/_apis/git/repositories/$newRepoId/importRequests?api-version=7.0  -Method Post -Body ($repoImportParameters | ConvertTo-Json) -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
                }
            }
        }
         break
         
         Set-Location -Path ./$name
         New-Item -ItemType Directory -Force -Path $sourceProjectName

         # Navigate to Project specific path 
         Set-Location -Path $sourceProjectName

         # Get JSON content from migration configuration
         Copy-Item "../../configuration4.json" -Destination .
         $configurationJson = Get-Content -Path "./configuration4.json" | ConvertFrom-Json
            
         # Script out Organization/Project/PAT details in Source and Destination config objects
         # Prepare as much as possible
         # Update Source for WorkItems
         $configurationJson.Source.Collection = $Url
         $configurationJson.Source.Project = $sourceProjectName
         $configurationJson.Source.AuthenticationMode = "AccessToken"
         $configurationJson.Source.PersonalAccessToken = $personalAccessToken

         # Update Destination for WorkItems
         $configurationJson.Target.Collection = $targetOrganization
         $configurationJson.Target.Project = $sourceProjectName
         $configurationJson.Target.AuthenticationMode = "AccessToken"
         $configurationJson.Target.PersonalAccessToken = $targetPersonalAccessToken

         $currentProject = $_

         # Update Endpoints for Pipelines
         $configurationJson.Endpoints.AzureDevOpsEndpoints | ForEach-Object {
            
            if ($_.Name -eq "Source") {
                $_.AccessToken = $personalAccessToken
                $_.Query.Parameters.TeamProject = $currentProject.name
                $_.Organisation = $Name
                $_.Project = $sourceProjectName
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