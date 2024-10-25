$sourceOrgName=""
$sourceProjectName= [uri]::EscapeDataString("")

$targetOrgName=""
$targetProjectName= [uri]::EscapeDataString("")

$PATSource=""
$PATSourceUser = ""

$b64EncodedSourcePAT = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PATSourceUser + ":" + $PATSource))

$PAT=""
$PATUser = ""

$b64EncodedPAT = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PATUser + ":" + $PAT))

$existingProject = Invoke-WebRequest -Uri https://dev.azure.com/$targetOrgName/_apis/projects/"$targetProjectName"?api-version=7.0  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPAT"}
$existingProjectId = ($existingProject.Content | ConvertFrom-Json).id

# Migrate Repos from Source
$sourceRepos = Invoke-WebRequest -Uri https://dev.azure.com/$sourceOrgName/$sourceProjectName/_apis/git/repositories?api-version=7.1-preview.1  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedSourcePAT"}
($sourceRepos.Content | ConvertFrom-Json).value | ForEach-Object { 
    
    #Check if repo existing in target project
    $sourceRepositoryName = [uri]::EscapeDataString($_.name)

    $Header = @{
                Authorization = ("Basic {0}" -f $b64EncodedPAT)
    }

    $EndpointURL = "https://dev.azure.com/$targetOrgName/$targetOrgName/_apis/serviceendpoint/endpoints"
    
    $existingRepo = @{}
    try {
        $existingRepoUrl = "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/git/repositories/$sourceRepositoryName" + "?api-version=7.1-preview.1"
        $existingRepo = Invoke-WebRequest -Uri $existingRepoUrl  -Method Get -ContentType "application/json" -Headers @{"Authorization"="Basic $b64EncodedPAT"}
        
        #Check if Repo is empty
        try {
            $existingRepoContents = Invoke-RestMethod "https://dev.azure.com/$targetOrgName/$targetOrgName/_apis/git/repositories/$sourceRepositoryName/items?recursionLevel=Full&api-version=6.0" -Headers $Header
        }
        catch {
            if ($_.ErrorDetails.Message -like "*Cannot find any branches*" ) {
                $Endpoint = @{}
                $Parameters = @{
                    Uri         = "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/serviceendpoint/endpoints?endpointNames=GitImport:$sourceProjectName$sourceRepositoryName&api-version=5.1-preview.2"
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
                        "url"           = "https://$sourceOrgName@dev.azure.com/$sourceOrgName/$sourceProjectName/_git/$sourceRepositoryName"
                        "authorization" = @{
                            "parameters" = @{
                                "username" = "$PATSourceUser"
                                "password" = "$PATSource"
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
                            $Endpoint = Invoke-RestMethod -Uri "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/serviceendpoint/endpoints?api-version=5.0-preview.2" -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 6) -Headers $Header -Method Post
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
                        "url"       = "https://$sourceOrgName@dev.azure.com/$sourceOrgName/$sourceProjectName/_git/$sourceRepositoryName"
                        "overwrite" = $false
                }
                    "tfvcSource"                             = $null
                    "serviceEndpointId"                      = $EndpointId
                }
                }
                $Parameters = @{
                    uri         = "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/git/repositories/$sourceRepositoryName/importRequests"
                    Method      = 'POST'
                    ContentType = "application/json"
                    Headers     = $Header
                    Body        = $Body
                }

                Try {
                    Invoke-RestMethod -Uri "https://dev.azure.com/$targetOrgName/$existingProjectId/_apis/git/repositories/$sourceRepositoryName/importRequests?api-version=5.0-preview.1" -Method Post -Body ($Body | ConvertTo-Json -Depth 5) -ContentType "application/json" -Headers $Header
                }
                Catch {
                    Write-Output "Could not import Repo $sourceRepositoryName : $_"
                }
            }
        }
    }
    catch {
        if (($_[0] | ConvertFrom-Json).typeName -eq "Microsoft.TeamFoundation.Git.Server.GitRepositoryNotFoundException, Microsoft.TeamFoundation.Git.Server") 
        {
            $newRepoParameters = @{
                name         = [uri]::UnescapeDataString($sourceRepositoryName) 
            }
            $newRepo = Invoke-WebRequest -Uri "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/git/repositories?api-version=7.0" -Method Post -ContentType "application/json" -Body ($newRepoParameters | ConvertTo-Json) -Headers @{"Authorization"="Basic $b64EncodedPAT"}
            
            $newRepo = $newRepo.Content | ConvertFrom-Json

            $Endpoint = @{}
            $EndpointId = ""
            $Parameters = @{
                Uri         = "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/serviceendpoint/endpoints?endpointNames=GitImport:$sourceProjectName$sourceRepositoryName&api-version=5.1-preview.2"
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
                    "url"           = "https://$sourceOrgName@dev.azure.com/$sourceOrgName/$sourceProjectName/_git/$sourceRepositoryName"
                    "authorization" = @{
                        "parameters" = @{
                            "username" = "$PATSourceUser"
                            "password" = "$PATSource"
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
                        $Endpoint = Invoke-RestMethod -Uri "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/serviceendpoint/endpoints?api-version=5.0-preview.2" -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 6) -Headers $Header -Method Post
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
                    "url"       = "https://$sourceOrgName@dev.azure.com/$sourceOrgName/$sourceProjectName/_git/$sourceRepositoryName"
                    "overwrite" = $false
                }
                "tfvcSource"                             = $null
                "serviceEndpointId"                      = $EndpointId
            }
            }
            $Parameters = @{
                uri         = "https://dev.azure.com/$targetOrgName/$targetProjectName/_apis/git/repositories/$sourceRepositoryName/importRequests"
                Method      = 'POST'
                ContentType = "application/json"
                Headers     = $Header
                Body        = $Body
            }

            Try {
                Invoke-RestMethod -Uri "https://dev.azure.com/$targetOrgName/$existingProjectId/_apis/git/repositories/$sourceRepositoryName/importRequests?api-version=5.0-preview.1" -Method Post -Body ($Body | ConvertTo-Json -Depth 5) -ContentType "application/json" -Headers $Header
            }
            Catch {
                Write-Output "Could not import Repo $sourceRepositoryName : $_"
            }
        }
    }
}