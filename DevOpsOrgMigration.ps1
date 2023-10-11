#Variables
$targetOrganization=""
$organizationName=""
$targetPersonalAccessToken=""
$targetPatUser = ""
$sourcePersonalAccessToken=""
$sourcePatUser = ""

# Parse Excel Values from Disconnected Organizations - TODO: Acquire PATS for source projects; Put into Excel
$CSVOrganizations = Import-Csv -Path ./organizations.csv

# LOOP For-Each list of Organizations #
# Create directory for Source DevOps Organization
foreach ($row in $CSVOrganizations)
{
    $name = $row.Name
    $Url = $row.Url

    $templateId = ""
    
    $b64EncodedPATTarget = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($targetPatUser + ":" + $targetPersonalAccessToken))
    $b64EncodedPATSource = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sourcePatUser + ":" + $sourcePersonalAccessToken))
    
    # Query for projects within an Organization
    $projects = Invoke-WebRequest -Uri https://dev.azure.com/$name/_apis/projects?api-version=7.0  -Method Get -ContentType "application-json" -Headers @{"Authorization"="Basic $b64EncodedPATSource"}
    $organizationDirectory = New-Item -ItemType Directory -Force -Path ./$name

    # For-Each list of Project in an Organization #
    # Create directory for each Project
    ($projects.Content | ConvertFrom-Json).value | ForEach-Object {
         $sourceProjectName = $_.name
         $sourceProjectId = $_.id
         $sourceProjectDescription = $_.description

         # Check if project exists in the target directory
         $existingProject = @{}
         $existingProjectId = ""
         try {
            $existingProject = Invoke-WebRequest -Uri https://dev.azure.com/$organizationName/_apis/projects/"$sourceProjectName"?api-version=7.0  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
         }
         catch { 
         
            if (($_[0] | ConvertFrom-Json).typeName -eq "Microsoft.TeamFoundation.Core.WebApi.ProjectDoesNotExistWithNameException, Microsoft.TeamFoundation.Core.WebApi") 
            {

                $sourceProcess = Invoke-WebRequest -Uri "https://dev.azure.com/$name/_apis/projects/$sourceProjectId/properties?keys=System.Process Template&api-version=7.0-preview.1"  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATSource"}
                
                $listTargetProcesses = Invoke-WebRequest -Uri "https://dev.azure.com/$organizationName/_apis/process/processes?api-version=7.0"  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}

                foreach ($process in ($listTargetProcesses.Content | ConvertFrom-Json).value) {
                    $sourceProcessName = ($sourceProcess.Content | ConvertFrom-Json).value[0].value
                    $migrationProcessName = $sourceProcessName + "Migration"
                    if ($migrationProcessName -eq $process.name) {
                       $templateId = $process.id
                    }
                }

                $projectParameters = @{
                    name             = $sourceProjectName
                    description      = $sourceProjectDescription
                    visibility       = "private"
                    capabilities     = @{
                        versioncontrol = @{
                          sourceControlType= "Git"
                        }
                        processTemplate        = @{
                            templateTypeId     = $templateId
                        }
                    }
                }

            #Create Project in Destination Organization
            $existingProjectBaseUrl = "https://dev.azure.com/$organizationName/_apis/projects/$sourceProjectName" + "?api-version=7.0"
            $existingProject = Invoke-WebRequest -Uri $existingProjectBaseUrl -Method Post -Body ($projectParameters | ConvertTo-Json -Depth 6) -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
            Start-Sleep -Seconds 5
            $existingProject = Invoke-WebRequest -Uri $existingProjectBaseUrl  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
        }
         }

         $existingProjectId = ($existingProject.Content | ConvertFrom-Json).id

        # Migrate Repos from Source
        $sourceRepos = Invoke-WebRequest -Uri https://dev.azure.com/$name/$sourceProjectName/_apis/git/repositories?api-version=7.1-preview.1  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATSource"}
        ($sourceRepos.Content | ConvertFrom-Json).value | ForEach-Object { 
            $sourceRepo = $_
            #Check if repo existing in target project
            $sourceRepositoryName = $_.name

            $Header = @{
                        Authorization = ("Basic {0}" -f $b64EncodedPATTarget)
            }

            $EndpointURL = "https://dev.azure.com/$organizationName/$existingProjectId/_apis/serviceendpoint/endpoints"
            
            $existingRepo = @{}
            try {
                $existingRepoUrl = "https://dev.azure.com/$organizationName/$sourceProjectName/_apis/git/repositories/$sourceRepositoryName" + "?api-version=7.1-preview.1"
                $existingRepo = Invoke-WebRequest -Uri $existingRepoUrl  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
                
                #Check if Repo is empty
                try {
                    $existingRepoContents = Invoke-RestMethod "https://dev.azure.com/$organizationName/$sourceProjectName/_apis/git/repositories/$sourceRepositoryName/items?recursionLevel=Full&api-version=6.0" -Headers $Header
                }
                catch {
                    if ($_.ErrorDetails.Message -like "*Cannot find any branches*" ) {
                        $encodedRepositoryName = [uri]::EscapeDataString($sourceRepositoryName)
                        $encodedSourceProjectName = [uri]::EscapeDataString($sourceProjectName)
                        $Endpoint = @{}
                        $Parameters = @{
                            Uri         = "https://dev.azure.com/$organizationName/$sourceProjectName/_apis/serviceendpoint/endpoints?endpointNames=GitImport:$sourceProjectName$sourceRepositoryName&api-version=5.1-preview.2"
                            Method      = "GET"
                            ContentType = "application/json"
                            Headers     = $Header
                        }
                        try {
                            $Endpoint = Invoke-RestMethod @Parameters

                            if ($Endpoint.count -eq 0) {
                              $Body = @{
                                "name"          = "GitImport:$sourceProjectName$sourceRepositoryName"
                                "type"          = "git"
                                "url"           = "https://$name@dev.azure.com/$name/$encodedSourceProjectName/_git/$encodedRepositoryName"
                                "authorization" = @{
                                    "parameters" = @{
                                        "username" = "$sourcePatUser"
                                        "password" = "$sourcePersonalAccessToken"
                                    }
                                    "scheme"     = "UsernamePassword"
                                }
                              }
                                $Parameters = @{
                                    Uri         = $EndpointURL
                                    Method      = "POST"
                                    ContentType = "application/json"
                                    Headers     = $Header
                                    Body        = $Body
                                }
                                
                                Try {
                                    $Endpoint = Invoke-RestMethod -Uri "https://dev.azure.com/$organizationName/$encodedSourceProjectName/_apis/serviceendpoint/endpoints?api-version=5.0-preview.2" -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 6) -Headers $Header -Method Post
                                    $EndpointId = $Endpoint.id

                                }
                                Catch {
                                    Write-Output "Could not create Endpoint: $_"
                                }
                            } else {
                                $EndpointId = $Endpoint.value[0].id
                            }
                        }
                        catch {
                            Write-Output "Error:$_"
                        }

                        $Body = @{
                        "parameters" = @{
                            "deleteServiceEndpointAfterImportIsDone" = $true
                            "gitSource"                              = @{
                                "url"       = "https://$name@dev.azure.com/$name/$encodedSourceProjectName/_git/$encodedRepositoryName"
                                "overwrite" = $false
                        }
                            "tfvcSource"                             = $null
                            "serviceEndpointId"                      = $EndpointId
                        }
                       }
                       $Parameters = @{
                            uri         = "https://dev.azure.com/$organizationName/$encodedSourceProjectName/_apis/git/repositories/$encodedRepositoryName/importRequests"
                            Method      = 'POST'
                            ContentType = "application/json"
                            Headers     = $Header
                            Body        = $Body
                        }

                        Try {
                            Invoke-RestMethod -Uri "https://dev.azure.com/$organizationName/$existingProjectId/_apis/git/repositories/$encodedRepositoryName/importRequests?api-version=5.0-preview.1" -Method Post -Body ($Body | ConvertTo-Json -Depth 5) -ContentType "application/json" -Headers $Header
                        }
                        Catch {
                            Write-Output "Could not import Repo $encodedRepositoryName : $_"
                        }
                    }
                }
                
            }
            catch {
                if (($_[0] | ConvertFrom-Json).typeName -eq "Microsoft.TeamFoundation.Git.Server.GitRepositoryNotFoundException, Microsoft.TeamFoundation.Git.Server") 
                {
                    $encodedSourceProjectName = [uri]::EscapeDataString($sourceProjectName)
                    $encodedRepositoryName = [uri]::EscapeDataString($sourceRepositoryName)
                    $newRepoParameters = @{
                        name        = $sourceRepo.name
                    }
                    $newRepo = Invoke-WebRequest -Uri "https://dev.azure.com/$organizationName/$encodedSourceProjectName/_apis/git/repositories?api-version=7.0" -Method Post -ContentType "application/json" -Body ($newRepoParameters | ConvertTo-Json) -Headers @{"Authorization"="Basic $b64EncodedPATTarget"}
                    
                    $newRepo = $newRepo.Content | ConvertFrom-Json

                    $Endpoint = @{}
                    $EndpointId = ""
                    $Parameters = @{
                        Uri         = "https://dev.azure.com/$organizationName/$encodedSourceProjectName/_apis/serviceendpoint/endpoints?endpointNames=GitImport:$sourceProjectName$sourceRepositoryName&api-version=5.1-preview.2"
                        Method      = "GET"
                        ContentType = "application/json"
                        Headers     = $Header
                    }
                    try {
                        $Endpoint = Invoke-RestMethod @Parameters

                        if ($Endpoint.count -eq 0) {
                         $Body = @{
                            "name"          = "GitImport:$sourceProjectName$sourceRepositoryName"
                            "type"          = "git"
                            "url"           = "https://$name@dev.azure.com/$name/$encodedSourceProjectName/_git/$encodedRepositoryName"
                            "authorization" = @{
                                "parameters" = @{
                                    "username" = "$sourcePatUser"
                                    "password" = "$sourcePersonalAccessToken"
                                }
                                "scheme"     = "UsernamePassword"
                            }
                          }
                            $Parameters = @{
                                Uri         = $EndpointURL
                                Method      = "POST"
                                ContentType = "application/json"
                                Headers     = $Header
                                Body        = ([System.Text.Encoding]::UTF8.GetBytes(( $Body | ConvertTo-Json )))
                            }
                            Try {
                                $Endpoint = Invoke-RestMethod -Uri "https://dev.azure.com/$organizationName/$encodedSourceProjectName/_apis/serviceendpoint/endpoints?api-version=5.0-preview.2" -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 6) -Headers $Header -Method Post
                                $EndpointId = $Endpoint.id
                            }
                            Catch {
                                Write-Output "Could not create Endpoint: $_"
                            }
                        } else {
                          $EndpointId = $Endpoint.value[0].id
                        }
                    }
                    catch {
                            Write-Output "Error:$_"
                    }
                    
                    $Body = @{
                    "parameters" = @{
                        "deleteServiceEndpointAfterImportIsDone" = $true
                        "gitSource"                              = @{
                            "url"       = "https://$name@dev.azure.com/$name/$encodedSourceProjectName/_git/$encodedRepositoryName"
                            "overwrite" = $false
                        }
                        "tfvcSource"                             = $null
                        "serviceEndpointId"                      = $EndpointId
                    }
                   }
                   $Parameters = @{
                        uri         = "https://dev.azure.com/$organizationName/$encodedSourceProjectName/_apis/git/repositories/$encodedRepositoryName/importRequests"
                        Method      = 'POST'
                        ContentType = "application/json"
                        Headers     = $Header
                        Body        = $Body
                    }

                    Try {
                        Invoke-RestMethod -Uri "https://dev.azure.com/$organizationName/$existingProjectId/_apis/git/repositories/$encodedRepositoryName/importRequests?api-version=5.0-preview.1" -Method Post -Body ($Body | ConvertTo-Json -Depth 5) -ContentType "application/json" -Headers $Header
                    }
                    Catch {
                        Write-Output "Could not import Repo $encodedRepositoryName : $_"
                    }
                }
            }
        }
         Set-Location -Path ./$name
         $directoryFolder = New-Item -ItemType Directory -Force -Path $sourceProjectName

         # Navigate to Project specific path 
         Set-Location -Path $sourceProjectName

         # Get JSON content from migration configuration
         Copy-Item "../../organizationMigrationConfiguration.json" -Destination .
         $configurationJson = Get-Content -Path "./organizationMigrationConfiguration.json" | ConvertFrom-Json
            
         # Script out Organization/Project/PAT details in Source and Destination config objects
         # Prepare as much as possible
         # Update Source for WorkItems
         $configurationJson.Source.Collection = $Url
         $configurationJson.Source.Project = $sourceProjectName
         $configurationJson.Source.AuthenticationMode = "AccessToken"
         $configurationJson.Source.PersonalAccessToken = $sourcePersonalAccessToken

         # Update Destination for WorkItems
         $configurationJson.Target.Collection = $targetOrganization
         $configurationJson.Target.Project = $sourceProjectName
         $configurationJson.Target.AuthenticationMode = "AccessToken"
         $configurationJson.Target.PersonalAccessToken = $targetPersonalAccessToken

         $currentProject = $_

         # Update Endpoints for Pipelines
         $configurationJson.Endpoints.AzureDevOpsEndpoints | ForEach-Object {
            
            if ($_.Name -eq "Source") {
                $_.AccessToken = $sourcePersonalAccessToken
                $_.Query.Parameters.TeamProject = $currentProject.name
                $_.Organisation = "https://dev.azure.com/$name/"
                $_.Project = $sourceProjectName
            }
            if ($_.Name -eq "Target") {
                $_.AccessToken = $targetPersonalAccessToken
                $_.Organisation = "https://dev.azure.com/$organizationName/"
                $_.Project = $currentProject.name
            }
         }

         ($configurationJson | ConvertTo-Json -depth 100).Replace("\u0027", "'").Replace("\u003c", "<").Replace("\u003e", ">") | set-content ./organizationMigrationConfiguration.json -Encoding UTF8

         # Execute Migration
         try {
             Write-Output "Executing Migration for $sourceProjectName"
             #C:\tools\MigrationTools\migration.exe execute --config ./configuration4.json | Out-File -FilePath ./output.txt -Append
             C:\Users\quinnmeagher\Downloads\MigrationTools-13.0.3\migration.exe execute --config ./organizationMigrationConfiguration.json | Out-File -FilePath ./output.txt -Append
         }
         catch {
             $Error[0].Message | Out-File -FilePath ./output.txt -Append
         }
         finally {
            #Reset to top level CWD
            Set-Location -Path ../../
         }
    }
}