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
    summary = "Missing required next_steps field."
    changed_files = @()
    verification_result = "Malformed fake response omitted one required field."
    risks = @("Fixture intentionally omits next_steps.")
}

$response | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -Path $outputPath
Write-Output "{`"event`":`"fake-codex-missing-field`",`"stdin_length`":$($stdin.Length)}"
exit 0
