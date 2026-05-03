$outputPath = ""

for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-o" -and ($i + 1) -lt $args.Count) {
        $outputPath = $args[$i + 1]
    }
}

$stdin = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($outputPath)) {
    Write-Error "Missing -o output path"
    exit 2
}

$response = [ordered]@{
    summary = "Structured Codex output was captured."
    changed_files = @("runner/codex.ps1")
    verification_result = "Structured fake Codex response parsed successfully."
    risks = @("Fake response only validates adapter parsing.")
    next_steps = @("Add malformed output fixtures in the next step.")
}

$response | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -Path $outputPath
Write-Output "{`"event`":`"fake-codex-structured`",`"stdin_length`":$($stdin.Length)}"
exit 0
