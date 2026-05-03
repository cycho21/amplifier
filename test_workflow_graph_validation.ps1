$ErrorActionPreference = "Stop"

function Invoke-InvalidWorkflow {
    param(
        [string]$WorkflowSpec,
        [string]$ExpectedMessage
    )

    $logOut = "logs/test-$([System.IO.Path]::GetFileNameWithoutExtension($WorkflowSpec))-000_template.json"
    $failed = $false

    try {
        & .\runner\workflow.ps1 `
            -TaskId "000_template" `
            -WorkflowSpec $WorkflowSpec `
            -LogOut $logOut
    } catch {
        $failed = $true

        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "Expected error containing '$ExpectedMessage', got '$($_.Exception.Message)'"
        }
    }

    if (-not $failed) {
        throw "Expected workflow spec to fail validation: $WorkflowSpec"
    }
}

Invoke-InvalidWorkflow `
    -WorkflowSpec "workflows/invalid-missing-dependency-workflow.yaml" `
    -ExpectedMessage "depends on unknown step 'architect'"

Invoke-InvalidWorkflow `
    -WorkflowSpec "workflows/invalid-duplicate-step-workflow.yaml" `
    -ExpectedMessage "Duplicate workflow step id: implementer"

Invoke-InvalidWorkflow `
    -WorkflowSpec "workflows/invalid-self-dependency-workflow.yaml" `
    -ExpectedMessage "depends on itself"

Invoke-InvalidWorkflow `
    -WorkflowSpec "workflows/invalid-cyclic-workflow.yaml" `
    -ExpectedMessage "Workflow dependency graph contains a cycle"

Write-Output "Workflow graph validation test passed."
