﻿function Get-EmbyActors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerUri,
        [Parameter(Mandatory=$true)]
        [string]$ApiKey
    )

    Invoke-RestMethod -Method Get -Uri "$ServerUri/emby/Persons/?api_key=$ApiKey" -Verbose
}

function New-ActorObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath
    )

    $Csv = Import-Csv -Path $CsvPath

    $ActorObject = @()
    foreach ($Object in $Csv) {
        $ActorObject += New-Object -TypeName psobject -Property @{
            Name = $Object.$alt
            EmbyId = $Object.EmbyId
            ThumbUrl = $Object.src
            PrimaryUrl = $Object.PrimaryUrl
        }
    }
    Write-Output $ActorObject
}

# Remove progress bar to speed up REST requests
$ProgressPreference = 'SilentlyContinue'

# Check settings file for config
$SettingsPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath 'settings_sort_jav.ini'))
$EmbyServerUri = ((Get-Content $SettingsPath) -match '^emby-server-uri').Split('=')[1]
$EmbyApiKey = ((Get-Content $SettingsPath) -match '^emby-api-key').Split('=')[1]
$R18ImportPath = ((Get-Content $SettingsPath) -match '^r18-export-csv-path').Split('=')[1]
$ActorExportPath = ((Get-Content $SettingsPath) -match '^actor-csv-export-path').Split('=')[1]

# Write Emby actors and id to object
Write-Output "Building Emby actor object..."
$EmbyActors = Get-EmbyActors -ServerUri $EmbyServerUri -ApiKey $EmbyApiKey
$EmbyActorObject = @()
for ($x = 0; $x -lt $EmbyActors.Items.Length; $x++) {
    $EmbyActorObject += New-Object -TypeName psobject -Property @{
        Name = $EmbyActors.Items.Name[$x]
        EmbyId = $EmbyActors.Items.Id[$x]
    }
}

# Import R18 actors and thumburls to object
Write-Output "Reading R18 object..."
$R18ActorObject = Import-Csv -Path $R18ImportPath

Write-Output "Building combined object, please wait..."
# Compare both Emby and R18 actors for matching actors, and combine to a single object
$ActorNames = @()
$ActorObject = @()
for ($x = 0; $x -lt $EmbyActorObject.Length; $x++) {
    $ActorNames += ($EmbyActorObject[$x].Name).ToLower()
    if ($ActorNames[$x] -notin $R18ActorObject.Name) {
        #Write-Host "Missing"
        $ActorObject += New-Object -TypeName psobject -Property @{
            Name = $EmbyActorObject[$x].Name
            EmbyId = $EmbyActorObject[$x].EmbyId
            ThumbUrl = ''
            PrimaryUrl = ''
        }
    }
    else {
        $Index = [array]::indexof(($R18ActorObject.Name).ToLower(), $ActorNames[$x])
        #Write-Host ""$EmbyActorObject[$x].Name" is index $Index"
        $ActorObject += New-Object -TypeName psobject -Property @{
            Name = $EmbyActorObject[$x].Name
            EmbyId = $EmbyActorObject[$x].EmbyId
            ThumbUrl = $R18ActorObject[$Index].ThumbUrl
            PrimaryUrl = $R18ActorObject[$Index].ThumbUrl
        }
    }
}

if (Test-Path $ActorExportPath) {
    Write-Host "File specified in actor-csv-export-path already exists. Overwrite with a new copy? "
    $Input = Read-Host "Your file will only be updated with new actresses if your select N   [y/N]"
}
else {
    $Input = 'y'
}

if ($Input -like 'y') {
    $ActorObject | Select-Object Name, EmbyId, ThumbUrl, PrimaryUrl | Export-Csv -Path $ActorExportPath -Force -NoTypeInformation
}

else {
    $ExistingActors = Import-Csv -Path $ActorExportPath
    $Count = 1
    foreach ($Actor in $ActorObject) {
        # If EmbyId already exists in the csv
        if ($Actor.EmbyId -in $ExistingActors.EmbyId) {
            # Do nothing
        }
        # If new actor (EmbyId) found, append to existing csv
        else {
            $Actor | Select-Object Name, EmbyId, ThumbUrl, PrimaryUrl | Export-Csv -Path $ActorExportPath -Append -NoClobber -NoTypeInformation
            Write-Output "($Count) Appending $Actor"
        }
        $Count++
    }
}