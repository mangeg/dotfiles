[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

oh-my-posh --init --shell pwsh --config "D:\Dev\Repos\dotfiles\poweshell\oh-my-posh-default.json" | Invoke-Expression

Import-Module -Name Terminal-Icons


<#
# PowerShell parameter completion shim for the dotnet CLI 
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Import-Module posh-git
Import-Module oh-my-posh
Set-Theme Paradox

Set-PSReadlineKeyHandler -Key Tab -Function Complete
Set-PSReadLineOption -BellStyle None

function Get-TerraformDirectory {
    $pathInfo = Microsoft.PowerShell.Management\Get-Location
    if (!$pathInfo -or ($pathInfo.Provider.Name -ne 'FileSystem')) {
        $null
    }
    else {
        $currentDir = Get-Item -LiteralPath $pathInfo -Force
        while ($currentDir) {
            $gitDirPath = Join-Path $currentDir.FullName .terraform
            if (Test-Path -LiteralPath $gitDirPath -PathType Container) {
                return $gitDirPath
            }

            $currentDir = $currentDir.Parent
        }
    }
}

[ScriptBlock]$oldPrompt = (Get-Item -Path Function:prompt).ScriptBlock
[ScriptBlock]$newPrompt = {
    (Get-Module oh-my-psh).SessionState | % $oldPrompt
    if (Get-TerraformDirectory) {
        $res = (terraform workspace show)
        Write-Host " (TWS: $($res))  "
    }
}
Set-Item -Path Function:prompt $newPrompt

New-Alias which get-command

New-Alias e explorer

New-Alias k kubectl
New-Alias d docker
New-Alias dc docker-compose
New-Alias t terraform

function kns([Parameter(ValueFromRemainingArguments = $true)]$params) { & kubectl config set-context --current --namespace=$params }
function kd([Parameter(ValueFromRemainingArguments = $true)]$params) { & kubectl describe $params }
function krm([Parameter(ValueFromRemainingArguments = $true)]$params) { & kubectl delete $params }
function kgns([Parameter(ValueFromRemainingArguments = $true)]$params) { & kubectl get namespaces $params }

function di([Parameter(ValueFromRemainingArguments = $true)]$params) { & docker images $params }
function drf([Parameter(ValueFromRemainingArguments = $true)]$params) { & docker rm -f @(d ps -a -q) $params }

New-Alias c choco
function co() { & choco outdated }
function cu() { & choco upgrade all }

Function Get-Something {
    [CmdletBinding()]
    Param([Parameter(ValueFromPipeline)]$item)

    Write-Host "You passed the parameter $item into the function"
}

Function base64 {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $textIn
    ) 
    
    $b = [System.Text.Encoding]::UTF8.GetBytes($textIn)
    $encoded = [System.Convert]::ToBase64String($b)
    return $encoded    
}

Function  debase64 {
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $textBase64In
    ) 
    
    $b = [System.Convert]::FromBase64String($textBase64In)
    $decoded = [System.Text.Encoding]::UTF8.GetString($b)
    return $decoded
}

Function update-dockerfiles {
    param (
        [Parameter(Mandatory = $true )][string]$solution
    )

    if (!(Test-Path $solution)) {
        Write-Error "`'$solution`' was not found"
        return
    }

    $slnItem = Get-Item $solution

    $dirs = @()
    $output = "COPY Directory.Build.props .`n"
    $output += "COPY `"$($slnItem.Name)`" `"$($slnItem.Name)`"" + "`n"
    Select-String -Path $solution -Pattern ', "(.*?\.csproj)"' | ForEach-Object {
        $_.Matches.Groups[1].Value | Sort-Object | ForEach-Object {
            $dirs += (Get-Item ($slnItem.Directory.FullName + "\" + $_) | Split-Path)
        }
        $_.Matches.Groups[1].Value.Replace("\", "/") | Sort-Object | ForEach-Object {    
            $output += "COPY `"$_`" `"$_`"`n"
        }  
    }
    Select-String -Path $solution -Pattern ', "(.*?\.dcproj)"' | ForEach-Object {
        $_.Matches.Groups[1].Value.Replace("\", "/") | Sort-Object | ForEach-Object {
            $output += "COPY `"$_`" `"$_`"`n"
        }  
    }

    $output += "RUN dotnet restore `"$($slnItem.Name)`""

    $dirs | ForEach-Object {
        $dockerfiles = Get-ChildItem -Path $_ -Filter "Dockerfile"
        foreach ($file in $dockerfiles) {
            Write-Output -Verbose "Updating $($file.FullName)"
            $content = (Get-Content $file) -join "`n"
            $newContent = $content -replace "(?ms)### START RESTORE ###(.*)### END RESTORE ###", "### START RESTORE ###`n$($output)`n### END RESTORE ###"
            $newContent | Set-Content $file
        }
    }
}
#>