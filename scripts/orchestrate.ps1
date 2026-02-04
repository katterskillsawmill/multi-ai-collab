<#
.SYNOPSIS
    Multi-AI Orchestrator - Claude Code spawns and reviews other AIs

.DESCRIPTION
    orchestrate "prompt" [ais]     - Query multiple AIs in parallel
    orchestrate review "prompt"    - Full review with all AIs
    orchestrate security "prompt"  - Security focus (Gemini + Grok)
    orchestrate quality "prompt"   - Quality focus (GPT-4 + Grok)

.EXAMPLE
    orchestrate "Review this auth code" gemini,grok
    orchestrate review "Check for issues in this PR"
#>

param(
    [Parameter(Position=0)]
    [string]$Prompt,

    [Parameter(Position=1)]
    [string]$AIs = "codex,gemini,grok"
)

$ScriptDir = $PSScriptRoot
$OutputDir = Join-Path $env:TEMP "ai-orchestrate"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Load API keys
$EnvFile = Join-Path $ScriptDir ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

function Start-AIQuery {
    param(
        [string]$AI,
        [string]$Prompt,
        [string]$OutputFile
    )

    $aiScript = Join-Path $ScriptDir "ai.ps1"

    switch ($AI.ToLower()) {
        "codex" {
            # Use Codex CLI
            $job = Start-Job -ScriptBlock {
                param($p, $out)
                $result = codex exec $p 2>&1
                $result | Out-File -FilePath $out -Encoding utf8
            } -ArgumentList $Prompt, $OutputFile
            return $job
        }
        "gemini" {
            $job = Start-Job -ScriptBlock {
                param($script, $p, $out)
                $result = & $script gemini $p 2>&1
                $result | Out-File -FilePath $out -Encoding utf8
            } -ArgumentList $aiScript, $Prompt, $OutputFile
            return $job
        }
        "grok" {
            $job = Start-Job -ScriptBlock {
                param($script, $p, $out)
                $result = & $script grok $p 2>&1
                $result | Out-File -FilePath $out -Encoding utf8
            } -ArgumentList $aiScript, $Prompt, $OutputFile
            return $job
        }
        "gpt4" {
            $job = Start-Job -ScriptBlock {
                param($script, $p, $out)
                $result = & $script gpt4 $p 2>&1
                $result | Out-File -FilePath $out -Encoding utf8
            } -ArgumentList $aiScript, $Prompt, $OutputFile
            return $job
        }
    }
}

# Parse AI list
$aiList = $AIs -split ','

# Handle presets
switch ($Prompt.ToLower()) {
    "review" {
        $Prompt = $args[0]
        $aiList = @("codex", "gemini", "grok")
    }
    "security" {
        $Prompt = $args[0]
        $aiList = @("gemini", "grok")
    }
    "quality" {
        $Prompt = $args[0]
        $aiList = @("codex", "grok")
    }
}

Write-Host "`n[Orchestrator] Querying: $($aiList -join ', ')" -ForegroundColor Cyan
Write-Host "[Orchestrator] Prompt: $($Prompt.Substring(0, [Math]::Min(100, $Prompt.Length)))..." -ForegroundColor DarkGray

# Start all AI queries in parallel
$jobs = @{}
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

foreach ($ai in $aiList) {
    $outputFile = Join-Path $OutputDir "$ai-$timestamp.txt"
    Write-Host "[Orchestrator] Starting $ai..." -ForegroundColor Yellow
    $jobs[$ai] = @{
        Job = Start-AIQuery -AI $ai -Prompt $Prompt -OutputFile $outputFile
        Output = $outputFile
    }
}

# Wait for all jobs with timeout
Write-Host "[Orchestrator] Waiting for responses..." -ForegroundColor DarkGray
$timeout = 120 # seconds
$jobs.Values | ForEach-Object {
    $_.Job | Wait-Job -Timeout $timeout | Out-Null
}

# Collect results
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "AI RESPONSES" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

$results = @{}
foreach ($ai in $jobs.Keys) {
    $outputFile = $jobs[$ai].Output
    $job = $jobs[$ai].Job

    Write-Host "`n### $($ai.ToUpper())" -ForegroundColor Yellow

    if (Test-Path $outputFile) {
        $content = Get-Content $outputFile -Raw
        if ($content) {
            Write-Host $content -ForegroundColor White
            $results[$ai] = $content
        } else {
            Write-Host "(No response)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "(Failed to get response)" -ForegroundColor Red
    }

    # Cleanup job
    $job | Remove-Job -Force -ErrorAction SilentlyContinue
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan

# Output results as JSON for Claude Code to parse
$jsonOutput = Join-Path $OutputDir "results-$timestamp.json"
$results | ConvertTo-Json | Out-File -FilePath $jsonOutput -Encoding utf8
Write-Host "[Orchestrator] Results saved to: $jsonOutput" -ForegroundColor DarkGray

# Return results object
return $results
