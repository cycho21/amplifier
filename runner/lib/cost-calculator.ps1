# Cost Calculator
# Calculates estimated costs from provider metadata (token usage)

$ErrorActionPreference = "Stop"

# Provider pricing table (as of 2026-04)
# Rates are tokens per $1 USD
$script:PricingTable = @{
    "gpt-4" = @{
        prompt_tokens_per_dollar = 33333    # $0.03 per 1k tokens
        completion_tokens_per_dollar = 16667 # $0.06 per 1k tokens
    }
    "gpt-4-turbo" = @{
        prompt_tokens_per_dollar = 100000   # $0.01 per 1k tokens
        completion_tokens_per_dollar = 33333 # $0.03 per 1k tokens
    }
    "gpt-3.5-turbo" = @{
        prompt_tokens_per_dollar = 200000   # $0.005 per 1k tokens
        completion_tokens_per_dollar = 100000 # $0.01 per 1k tokens
    }
    "claude-sonnet-4-5" = @{
        # Anthropic pricing (estimated - Claude CLI doesn't expose tokens)
        prompt_tokens_per_dollar = 33333    # $0.03 per 1k tokens (estimate)
        completion_tokens_per_dollar = 16667 # $0.06 per 1k tokens (estimate)
    }
    "claude-opus-4" = @{
        prompt_tokens_per_dollar = 6667     # $0.15 per 1k tokens (estimate)
        completion_tokens_per_dollar = 3333  # $0.30 per 1k tokens (estimate)
    }
}

function Get-StepCost {
    <#
    .SYNOPSIS
    Calculates cost from provider_metadata tokens

    .PARAMETER ProviderMetadata
    Hashtable with model, prompt_tokens, completion_tokens

    .PARAMETER Currency
    Currency for cost calculation (default: USD)

    .OUTPUTS
    Float: estimated cost in specified currency
    #>
    param(
        [hashtable]$ProviderMetadata,
        [string]$Currency = "USD"
    )

    # Return 0 if no metadata (dry-run mode)
    if ($null -eq $ProviderMetadata -or $ProviderMetadata.Count -eq 0) {
        return 0
    }

    # Return 0 if no model specified
    if (-not ($ProviderMetadata.PSObject.Properties.Name -contains "model")) {
        Write-Verbose "No model in provider metadata. Returning 0 cost."
        return 0
    }

    $model = $ProviderMetadata.model

    # Return 0 if model not in pricing table
    if (-not $script:PricingTable.ContainsKey($model)) {
        Write-Warning "No pricing data for model: $model. Returning 0 cost."
        return 0
    }

    $pricing = $script:PricingTable[$model]

    # Extract token counts (default to 0 if not present)
    $promptTokens = if ($ProviderMetadata.PSObject.Properties.Name -contains "prompt_tokens") {
        $ProviderMetadata.prompt_tokens
    } else {
        0
    }

    $completionTokens = if ($ProviderMetadata.PSObject.Properties.Name -contains "completion_tokens") {
        $ProviderMetadata.completion_tokens
    } else {
        0
    }

    # Calculate cost: tokens / tokens_per_dollar
    $promptCost = $promptTokens / $pricing.prompt_tokens_per_dollar
    $completionCost = $completionTokens / $pricing.completion_tokens_per_dollar
    $totalCost = $promptCost + $completionCost

    # Round to 6 decimal places for precision
    return [Math]::Round($totalCost, 6)
}

function Get-WorkflowTotalCost {
    <#
    .SYNOPSIS
    Sums step costs to get workflow total

    .PARAMETER StepCosts
    Array of step cost objects with estimated_cost field

    .OUTPUTS
    Float: total cost across all steps
    #>
    param([array]$StepCosts)

    $total = 0

    foreach ($stepCost in $StepCosts) {
        if ($stepCost.Keys -contains "estimated_cost") {
            $total += $stepCost.estimated_cost
        }
    }

    # Round to 6 decimal places
    return [Math]::Round($total, 6)
}

# Functions are available when dot-sourced with:
# . .\runner\lib\cost-calculator.ps1
