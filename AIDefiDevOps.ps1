#requires -Version 5.1

<#
.SYNOPSIS
    AI-powered DeFi Strategy Generator with DevOps integration
.DESCRIPTION
    Generates DeFi trading strategies using AI and implements basic DevOps practices.
#>

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFile = "$(Get-Date -Format 'yyyy-MM-dd')_AIDeFiDevOps.log"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "INFO"  { Write-Host $logMessage -ForegroundColor Green }
        "WARN"  { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "DEBUG" { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage
}

function Get-APIKey {
    [CmdletBinding()]
    param()
    
    $apiKey = Read-Host -Prompt "Please enter your OpenRouter API key" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey)
    $plainApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    return $plainApiKey
}

function Test-APIKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApiKey
    )
    
    try {
        $headers = @{
            "Authorization" = "Bearer $ApiKey"
            "Content-Type" = "application/json"
        }
        
        $body = @{
            "model" = "qwen/qwen3-32b" 
            "messages" = @(
                @{
                    "role" = "user"
                    "content" = "Just reply with 'API key is valid' if you can see this message."
                }
            )
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Headers $headers -Body $body
        
        if ($response.choices -and $response.choices[0].message.content -like "*API key is valid*") {
            Write-Log -Message "API key successfully validated" -Level "INFO"
            return $true
        } else {
            Write-Log -Message "API key validation failed - unexpected response" -Level "ERROR"
            return $false
        }
    } catch {
        Write-Log -Message "API key validation failed: $_" -Level "ERROR"
        return $false
    }
}

function Get-AIResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApiKey,
        
        [Parameter(Mandatory=$true)]
        [string]$Prompt
    )
    
    try {
        Write-Log -Message "Sending prompt to AI: $($Prompt.Substring(0, [Math]::Min(50, $Prompt.Length)))..." -Level "DEBUG"
        
        $headers = @{
            "Authorization" = "Bearer $ApiKey"
            "Content-Type" = "application/json"
        }
        
        $body = @{
            "model" = "qwen/qwen3-32b"
            "messages" = @(
                @{
                    "role" = "system"
                    "content" = "You are a DeFi strategy expert with deep knowledge of blockchain, smart contracts, and trading strategies. Your recommendations are specific, actionable, and quantitative."
                },
                @{
                    "role" = "user"
                    "content" = $Prompt
                }
            )
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Headers $headers -Body $body
        
        Write-Log -Message "Received AI response" -Level "DEBUG"
        return $response.choices[0].message.content
    } catch {
        Write-Log -Message "Error getting AI response: $_" -Level "ERROR"
        return "Error: Failed to get AI response"
    }
}

function Get-CryptoPrices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Coins = @("bitcoin", "ethereum", "binancecoin", "solana", "cardano")
    )
    
    try {
        Write-Log -Message "Fetching current crypto prices" -Level "INFO"
        $coinsParam = $Coins -join ","
        $response = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/simple/price?ids=$coinsParam&vs_currencies=usd" -Method Get
        
        $priceTable = @()
        foreach ($coin in $Coins) {
            if ($response.$coin.usd) {
                $priceObject = [PSCustomObject]@{
                    Coin = $coin
                    PriceUSD = $response.$coin.usd
                }
                $priceTable += $priceObject
            }
        }
        
        return $priceTable
    } catch {
        Write-Log -Message "Error fetching crypto prices: $_" -Level "ERROR"
        return $null
    }
}

function Format-Strategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$StrategyText,
        
        [Parameter(Mandatory=$true)]
        [string]$StrategyType,
        
        [Parameter(Mandatory=$true)]
        [datetime]$GeneratedAt
    )
    
    $strategy = [PSCustomObject]@{
        Type = $StrategyType
        Content = $StrategyText
        GeneratedAt = $GeneratedAt
        StrategyID = [guid]::NewGuid().ToString()
    }
    
    return $strategy
}

function Save-Strategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Strategy
    )
    
    $strategiesDir = ".\Strategies"
    if (-not (Test-Path -Path $strategiesDir)) {
        New-Item -Path $strategiesDir -ItemType Directory | Out-Null
    }
    
    $fileName = "$($Strategy.GeneratedAt.ToString('yyyyMMdd_HHmmss'))_$($Strategy.Type)_$($Strategy.StrategyID.Substring(0,8)).json"
    $filePath = Join-Path -Path $strategiesDir -ChildPath $fileName
    
    $Strategy | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath
    Write-Log -Message "Strategy saved to $filePath" -Level "INFO"
    
    return $filePath
}

function Get-DeFiStrategies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApiKey,
        
        [Parameter(Mandatory=$false)]
        [int]$NumberOfStrategies = 2,
        
        [Parameter(Mandatory=$false)]
        [string[]]$StrategyTypes = @("Yield Farming", "Arbitrage", "Liquidity Mining")
    )
    
    $strategies = @()
    $prices = Get-CryptoPrices
    
    if (-not $prices) {
        Write-Log -Message "Unable to fetch crypto prices, using generic prompts" -Level "WARN"
    }
    
    for ($i = 0; $i -lt [Math]::Min($NumberOfStrategies, $StrategyTypes.Count); $i++) {
        $strategyType = $StrategyTypes[$i]
        Write-Log -Message "Generating $strategyType strategy" -Level "INFO"
        
        $prompt = "Generate a detailed $strategyType strategy for DeFi that can be implemented today. "
        
        if ($prices) {
            $prompt += "Current prices: "
            foreach ($price in $prices) {
                $prompt += "$($price.Coin): $$$($price.PriceUSD), "
            }
        }
        
        $prompt += @"
Include the following:
1. Specific tokens/platforms to use
2. Entry and exit conditions with specific thresholds
3. Risk management parameters (stop-loss, position sizing)
4. Expected ROI with timeframe
5. Step-by-step implementation instructions

Format your response in well-structured sections with headers.
"@
        
        $response = Get-AIResponse -ApiKey $ApiKey -Prompt $prompt
        $strategy = Format-Strategy -StrategyText $response -StrategyType $strategyType -GeneratedAt (Get-Date)
        $filePath = Save-Strategy -Strategy $strategy
        
        $strategies += $strategy
    }
    
    return $strategies
}

function Show-DeFiDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$Strategies,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject[]]$Prices
    )
    
    Clear-Host
    
    Write-Host "========================================================" -ForegroundColor Blue
    Write-Host "                AI-POWERED DEFI DASHBOARD                " -ForegroundColor Blue
    Write-Host "========================================================" -ForegroundColor Blue
    Write-Host ""
    
    if ($Prices) {
        Write-Host "CURRENT CRYPTO PRICES:" -ForegroundColor Cyan
        foreach ($price in $Prices) {
            Write-Host "  $($price.Coin): " -NoNewline
            Write-Host "$" + $price.PriceUSD.ToString("N2") -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    Write-Host "GENERATED STRATEGIES:" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i = 0; $i -lt $Strategies.Count; $i++) {
        Write-Host "STRATEGY $($i+1): $($Strategies[$i].Type)" -ForegroundColor Green
        Write-Host "Generated: $($Strategies[$i].GeneratedAt)" -ForegroundColor Gray
        Write-Host "ID: $($Strategies[$i].StrategyID)" -ForegroundColor Gray
        Write-Host "----------------------------------------" -ForegroundColor Gray
        
        # Display a preview of the strategy content
        $preview = $Strategies[$i].Content
        if ($preview.Length -gt 300) {
            $preview = $preview.Substring(0, 300) + "..."
        }
        Write-Host $preview
        
        Write-Host ""
        Write-Host "Full strategy saved to: .\Strategies\*$($Strategies[$i].StrategyID.Substring(0,8)).json" -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Host "========================================================" -ForegroundColor Blue
}

# Main script execution
Write-Host "AI-Powered DeFi Strategy Generator with DevOps Integration" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# Setup logging
$logDir = ".\Logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}
$logFile = Join-Path -Path $logDir -ChildPath "$(Get-Date -Format 'yyyy-MM-dd')_AIDeFiDevOps.log"
Write-Log -Message "Script started" -LogFile $logFile

# Get API key
$apiKey = Get-APIKey
if (-not (Test-APIKey -ApiKey $apiKey)) {
    Write-Host "Invalid API key. Please check your OpenRouter API key and try again." -ForegroundColor Red
    exit 1
}

# Get current crypto prices
$prices = Get-CryptoPrices

# Generate DeFi strategies
Write-Log -Message "Generating DeFi strategies..." -Level "INFO"
$strategies = Get-DeFiStrategies -ApiKey $apiKey -NumberOfStrategies 2

# Show dashboard
Show-DeFiDashboard -Strategies $strategies -Prices $prices

Write-Log -Message "Script completed successfully" -Level "INFO"
Write-Host ""
Write-Host "All strategies have been saved to the Strategies directory." -ForegroundColor Green
Write-Host "Logs have been saved to $logFile" -ForegroundColor Green
