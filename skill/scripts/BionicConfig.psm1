$script:ConfigPath = Join-Path $PSScriptRoot "..\config.json"

function Get-BionicConfig {
    $defaults = [ordered]@{
        DefaultModel = ""
        Port         = 1234
        Temperature  = 0.2
        MaxTokens    = 4096
    }
    if (Test-Path $script:ConfigPath) {
        try {
            $loaded = Get-Content -Raw -Path $script:ConfigPath | ConvertFrom-Json
            foreach ($key in @($defaults.Keys)) {
                if ($loaded.PSObject.Properties.Name -contains $key -and $null -ne $loaded.$key -and $loaded.$key -ne "") {
                    $defaults[$key] = $loaded.$key
                }
            }
        } catch {
            # corrupt/unreadable config -- fall back to defaults silently
        }
    }
    return $defaults
}

function Set-BionicConfig {
    param([Parameter(Mandatory=$true)][hashtable]$Config)
    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

function Get-BionicConfigPath {
    return $script:ConfigPath
}

Export-ModuleMember -Function Get-BionicConfig, Set-BionicConfig, Get-BionicConfigPath
