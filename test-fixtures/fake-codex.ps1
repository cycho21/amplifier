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

Set-Content -Encoding utf8 -Path $outputPath -Value "fake codex final message"
Write-Output "{`"event`":`"fake-codex`",`"stdin_length`":$($stdin.Length)}"
exit 0
