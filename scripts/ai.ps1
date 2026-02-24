<#
.SYNOPSIS
    Multi-AI CLI - Query Claude, GPT-4, Gemini, Grok from command line

.DESCRIPTION
    ai claude "your question"     - Ask Claude
    ai gpt4 "your question"       - Ask GPT-4
    ai gemini "your question"     - Ask Gemini
    ai grok "your question"       - Ask Grok
    ai all "your question"        - Ask all AIs
    ai notes [issue#]             - Check notes on an issue/PR
    ai post [issue#] "message"    - Post comment to issue/PR
    ai tag [issue#] claude "msg"  - Post @ai:claude tag to issue
    ai context                    - Show current repo context

    Use --context flag to auto-include repo context:
    ai claude --context "Review this"

.EXAMPLE
    ai claude "Review this code for architectural issues"
    ai claude --context "What should I improve?"
    ai notes 42
    ai tag 42 gpt4 "What patterns would improve this?"
#>

param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Args,

    [switch]$Context,

    [string]$Preset
)

# Load API keys from environment or .env file
$EnvFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

$ANTHROPIC_KEY = $env:ANTHROPIC_API_KEY
$OPENAI_KEY = $env:OPENAI_API_KEY
$GOOGLE_KEY = $env:GOOGLE_API_KEY
$XAI_KEY = $env:XAI_API_KEY

# Save $Preset before loading presets.ps1 (its param block would overwrite it)
$savedPreset = $Preset

# Load presets (definitions and functions only)
. (Join-Path $PSScriptRoot "presets.ps1")

# Load KB functions (for fact-checking in debates)
$kbFunctions = Join-Path $PSScriptRoot "kb-functions.ps1"
if (Test-Path $kbFunctions) {
    . $kbFunctions
}

# Restore $Preset
$Preset = $savedPreset

# Colors
function Write-AI { param($icon, $name, $color) Write-Host "`n$icon " -NoNewline; Write-Host $name -ForegroundColor $color }
function Write-Response { param($text) Write-Host $text -ForegroundColor White }
function Write-Err { param($msg) Write-Host "ERROR: $msg" -ForegroundColor Red }

# Context Gathering
function Get-RepoContext {
    $context = @()

    # Git status
    $gitStatus = git status --short 2>$null
    if ($LASTEXITCODE -eq 0) {
        $branch = git branch --show-current 2>$null
        $context += "BRANCH: $branch"

        if ($gitStatus) {
            $context += "CHANGED FILES:"
            $context += $gitStatus | Select-Object -First 20
        }
    }

    # Recent commits
    $recentCommits = git log --oneline -5 2>$null
    if ($LASTEXITCODE -eq 0 -and $recentCommits) {
        $context += ""
        $context += "RECENT COMMITS:"
        $context += $recentCommits
    }

    # Current diff (limited)
    $diff = git diff --stat 2>$null
    if ($LASTEXITCODE -eq 0 -and $diff) {
        $context += ""
        $context += "DIFF SUMMARY:"
        $context += $diff | Select-Object -First 15
    }

    # Check for README
    if (Test-Path "README.md") {
        $readme = Get-Content "README.md" -TotalCount 30 | Out-String
        $context += ""
        $context += "README (first 30 lines):"
        $context += $readme
    }

    # Check for package.json or pubspec.yaml
    if (Test-Path "package.json") {
        $pkg = Get-Content "package.json" | ConvertFrom-Json
        $context += ""
        $context += "PROJECT: $($pkg.name) v$($pkg.version)"
    }
    if (Test-Path "pubspec.yaml") {
        $context += ""
        $context += "FLUTTER PROJECT (pubspec.yaml found)"
    }

    return $context -join "`n"
}

function Show-Context {
    Write-Host "`nREPO CONTEXT" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor DarkGray
    $ctx = Get-RepoContext
    Write-Host $ctx -ForegroundColor White
}

# API Callers
function Invoke-Claude {
    param([string]$Prompt)

    if (-not $ANTHROPIC_KEY) { Write-Err "ANTHROPIC_API_KEY not set"; return $null }

    $body = @{
        model = "claude-sonnet-4-20250514"
        max_tokens = 2000
        messages = @(@{ role = "user"; content = $Prompt })
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers @{
            "Content-Type" = "application/json"
            "x-api-key" = $ANTHROPIC_KEY
            "anthropic-version" = "2023-06-01"
        } -Body $body
        return $response.content[0].text
    } catch {
        Write-Err "Claude API: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-GPT4 {
    param([string]$Prompt)

    if (-not $OPENAI_KEY) { Write-Err "OPENAI_API_KEY not set"; return $null }

    $body = @{
        model = "gpt-4o"
        max_tokens = 2000
        messages = @(
            @{ role = "system"; content = "You are GPT-4, an expert code reviewer focusing on code quality and best practices." }
            @{ role = "user"; content = $Prompt }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $OPENAI_KEY"
        } -Body $body
        return $response.choices[0].message.content
    } catch {
        Write-Err "GPT-4 API: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-Gemini {
    param([string]$Prompt)

    if (-not $GOOGLE_KEY) { Write-Err "GOOGLE_API_KEY not set"; return $null }

    $body = @{
        contents = @(@{
            parts = @(@{ text = $Prompt })
        })
        generationConfig = @{ maxOutputTokens = 2000 }
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=$GOOGLE_KEY" -Method Post -Headers @{
            "Content-Type" = "application/json"
        } -Body $body
        return $response.candidates[0].content.parts[0].text
    } catch {
        Write-Err "Gemini API: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-Grok {
    param([string]$Prompt)

    if (-not $XAI_KEY) { Write-Err "XAI_API_KEY not set"; return $null }

    $body = @{
        model = "grok-2-latest"
        max_tokens = 2000
        messages = @(
            @{ role = "system"; content = "You are Grok, an AI that thinks differently. Find unconventional issues and be slightly witty." }
            @{ role = "user"; content = $Prompt }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "https://api.x.ai/v1/chat/completions" -Method Post -Headers @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $XAI_KEY"
        } -Body $body
        return $response.choices[0].message.content
    } catch {
        Write-Err "Grok API: $($_.Exception.Message)"
        return $null
    }
}

# ============================================================================
# CLI WRAPPER FUNCTIONS (for Multi-AI Orchestration)
# These use CLI tools with their own auth - NO API KEYS NEEDED in this script
# ============================================================================

function Invoke-CodexCLI {
    param([string]$Prompt)

    # Write prompt to temp file for WSL
    $tempFile = [System.IO.Path]::GetTempFileName()
    $Prompt | Set-Content $tempFile -Encoding UTF8 -NoNewline

    try {
        $wslPath = (wsl wslpath -u ($tempFile.Replace('\', '/'))).Trim()
        # Use -o to capture output to file, --skip-git-repo-check for non-repo contexts
        $outputFile = "/tmp/codex-output-$([System.IO.Path]::GetRandomFileName()).txt"
        $null = wsl bash -c "cat '$wslPath' | codex exec --skip-git-repo-check -o '$outputFile' - 2>/dev/null"

        # Read the output file
        $result = wsl bash -c "cat '$outputFile' 2>/dev/null && rm -f '$outputFile'"

        # Handle array output - join lines into single string
        if ($result -is [array]) {
            return ($result -join "`n")
        }
        return $result
    } catch {
        Write-Err "Codex CLI: $($_.Exception.Message)"
        return "[Codex CLI error - ensure codex is installed in WSL and authenticated]"
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

function Invoke-GeminiCLI {
    param([string]$Prompt)

    try {
        # Write to temp file to avoid escaping issues
        $tempFile = [System.IO.Path]::GetTempFileName()
        $Prompt | Set-Content $tempFile -Encoding UTF8 -NoNewline

        # Use full path to gemini CLI (npm global bin)
        $npmBin = Join-Path $env:APPDATA "npm"
        $geminiCmd = Join-Path $npmBin "gemini.cmd"

        # Use gemini CLI with file input via cmd
        $result = cmd /c "type `"$tempFile`" | `"$geminiCmd`" 2>nul"
        Remove-Item $tempFile -ErrorAction SilentlyContinue

        # Handle array output - join lines into single string
        if ($result -is [array]) {
            return ($result -join "`n")
        }
        return $result
    } catch {
        Write-Err "Gemini CLI: $($_.Exception.Message)"
        return "[Gemini CLI error - ensure gemini CLI is installed and authenticated]"
    }
}

function Invoke-ClaudeCLI {
    param([string]$Prompt)

    try {
        # Prepend instruction to prevent agentic mode - Claude CLI otherwise uses tools
        # which causes --print output to be empty (tools output goes elsewhere)
        $prefixedPrompt = @"
IMPORTANT: Respond with text only. Do NOT use any tools (Read, Bash, Edit, etc).
Analyze the content below and provide your response as plain text.

$Prompt
"@

        # Write prompt to temp file to handle long prompts (command-line has ~8191 char limit)
        $tempFile = [System.IO.Path]::GetTempFileName()
        $prefixedPrompt | Set-Content $tempFile -Encoding UTF8 -NoNewline

        # Use full path to claude CLI (npm global bin)
        $npmBin = Join-Path $env:APPDATA "npm"
        $claudeCmd = Join-Path $npmBin "claude.cmd"

        # Use direct stdin redirection which handles very long content better than piping
        # The < redirection bypasses cmd pipe buffer limits
        $result = cmd /c "`"$claudeCmd`" --print < `"$tempFile`" 2>nul"

        Remove-Item $tempFile -ErrorAction SilentlyContinue

        # Handle array output - join lines into single string
        if ($result -is [array]) {
            return ($result -join "`n")
        }
        return $result
    } catch {
        Write-Err "Claude CLI: $($_.Exception.Message)"
        return "[Claude CLI error - ensure claude is installed and authenticated]"
    }
}

# ============================================================================
# BRAINSTORM HELPER FUNCTIONS
# ============================================================================

function Invoke-ProviderWithRetry {
    param(
        [scriptblock]$InvokeBlock,
        [string]$Prompt,
        [string]$ProviderName,
        [int]$MaxRetries = 2,
        [int]$DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
        $response = & $InvokeBlock $Prompt

        # Check for empty/null/whitespace/error responses
        if ($response -and $response.Trim() -ne '' -and
            $response -notmatch '^\[.*error.*\]$' -and
            $response -notmatch '^\[No response') {
            return $response
        }

        if ($attempt -le $MaxRetries) {
            Write-Host "  [$ProviderName] Empty response (attempt $attempt/$($MaxRetries+1)), retrying in ${DelaySeconds}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
            $DelaySeconds = [math]::Min($DelaySeconds * 2, 30)
        }
    }

    Write-Host "  [$ProviderName] WARNING: Empty after $($MaxRetries+1) attempts" -ForegroundColor Red
    return "[No response from $ProviderName after $($MaxRetries+1) attempts]"
}

function Test-ProviderHealth {
    param([string[]]$Providers)

    $npmBin = Join-Path $env:APPDATA "npm"

    $ProviderTestMap = @{
        "codex"  = {
            $out = wsl bash -c "echo 'Say OK' | codex exec --skip-git-repo-check - 2>&1"
            return ($LASTEXITCODE -eq 0 -and $out -and ($out | Out-String).Trim() -ne '')
        }
        "gemini" = {
            $geminiCmd = Join-Path $npmBin "gemini.cmd"
            $out = cmd /c "echo Say OK | `"$geminiCmd`" 2>nul"
            return ($out -and ($out | Out-String).Trim() -ne '')
        }
        "claude" = {
            $claudeCmd = Join-Path $npmBin "claude.cmd"
            $out = cmd /c "echo IMPORTANT: Respond with text only. Do NOT use any tools. Say OK. | `"$claudeCmd`" --print 2>nul"
            return ($out -and ($out | Out-String).Trim() -ne '')
        }
    }

    # Login instructions for each provider
    $ProviderLoginHelp = @{
        "codex"  = "    To fix Codex:`n      1. Open WSL:  wsl bash`n      2. Run:       codex auth login`n      3. Or retry - Codex often fails on first call but succeeds on retry."
        "gemini" = "    To fix Gemini:`n      1. Run:  gemini auth login`n      2. Or check settings at: ~/.gemini/settings.json"
        "claude" = "    To fix Claude:`n      1. Run:  claude auth login`n      2. Or check: claude config list"
    }

    $ProviderColors = @{
        "codex" = "Green"; "gemini" = "Blue"; "claude" = "Magenta"
    }

    Write-Host "`n[Pre-Flight Check] Verifying $($Providers.Count) providers..." -ForegroundColor Cyan
    $failedProviders = @()

    foreach ($provider in $Providers) {
        if (-not $ProviderTestMap.ContainsKey($provider)) {
            Write-Host "  [$provider] Unknown provider - skipping" -ForegroundColor Red
            $failedProviders += $provider
            continue
        }

        $color = if ($ProviderColors[$provider]) { $ProviderColors[$provider] } else { "White" }
        Write-Host "  [$provider] " -NoNewline -ForegroundColor $color
        Write-Host "Checking... " -NoNewline -ForegroundColor DarkGray

        # Try up to 2 attempts (Codex often fails first call then succeeds)
        $passed = $false
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                $healthy = & $ProviderTestMap[$provider]
                if ($healthy) {
                    $passed = $true
                    break
                }
            } catch {}

            if ($attempt -eq 1) {
                Write-Host "retry... " -NoNewline -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }

        if ($passed) {
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "FAILED" -ForegroundColor Red
            $failedProviders += $provider
        }
    }

    if ($failedProviders.Count -gt 0) {
        Write-Host "`n[BLOCKED] All $($Providers.Count) providers must be healthy before the debate can start." -ForegroundColor Red
        Write-Host "Failed providers: $($failedProviders -join ', ')" -ForegroundColor Red
        Write-Host ""
        foreach ($fp in $failedProviders) {
            if ($ProviderLoginHelp[$fp]) {
                Write-Host "  --- $($fp.ToUpper()) ---" -ForegroundColor Yellow
                Write-Host $ProviderLoginHelp[$fp] -ForegroundColor DarkGray
            }
        }
        Write-Host ""
        Write-Host "Fix the above issues, then re-run the brainstorm." -ForegroundColor Yellow
        return $null  # Signal: do NOT proceed
    }

    Write-Host "  All $($Providers.Count) providers healthy!" -ForegroundColor Green
    return $Providers
}

# ============================================================================
# MULTI-AI BRAINSTORM ORCHESTRATION
# ============================================================================

function Start-AIBrainstorm {
    param(
        [string]$Topic,
        [int]$Rounds = 3,
        [string]$OutputDir = ".ai-notes",
        [switch]$Sequential,
        [string[]]$Providers = @("codex", "gemini", "claude"),  # All 3 CLI providers debate by default
        [string]$PR,
        [string]$Issue,
        [switch]$PostResults,
        [ValidateSet("md", "json", "html", "slack", "discord")]
        [string]$OutputFormat = "md",
        [string]$WebhookUrl,
        [switch]$FactCheck  # Enable KB context for fact-checking
    )

    # Create session directory
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    # Use timestamped filename to preserve all sessions
    $fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $sessionFile = Join-Path $OutputDir "brainstorm-$fileTimestamp.md"
    $latestLink = Join-Path $OutputDir "session.md"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Fetch GitHub context if PR or Issue specified
    $githubContext = ""
    if ($PR -or $Issue) {
        $githubContext = Get-GitHubBrainstormContext -PR $PR -Issue $Issue
    }

    # Initialize session log
    $header = @"
# AI Brainstorming Session
**Started:** $timestamp
**Topic:** $Topic
**Mode:** $(if ($Sequential) { "Sequential" } else { "Parallel" })
**Providers:** $($Providers -join ", ")
$(if ($PR) { "**PR:** #$PR" })
$(if ($Issue) { "**Issue:** #$Issue" })

---
$(if ($githubContext) { "`n## GitHub Context`n$githubContext`n---" })
"@
    $header | Set-Content $sessionFile

    # Get KB context if fact-checking enabled
    $kbContext = ""
    if ($FactCheck -and (Get-Command Format-KBContext -ErrorAction SilentlyContinue)) {
        Write-Host "[+] Loading KB context for fact-checking..." -ForegroundColor DarkGray
        $kbContext = Format-KBContext -Topic $Topic

        # Check for conflicts before starting
        $conflicts = Test-DecisionConflict -Proposal $Topic
        if ($conflicts.HasConflicts) {
            Write-Host "[!] WARNING: $($conflicts.ConflictCount) potential conflict(s) detected!" -ForegroundColor Yellow
            foreach ($c in $conflicts.Conflicts) {
                $conflictDesc = if ($c.ExistingDecision) { $c.ExistingDecision } else { $c.Feature }
                Write-Host "    - [$($c.Type)] $conflictDesc" -ForegroundColor Yellow
            }
        }

        # Add KB context to session file
        Add-Content $sessionFile "`n## Knowledge Base Context`n$kbContext`n---"
    }

    Write-Host "`n[Brainstorm Session Started]" -ForegroundColor Cyan
    Write-Host "Topic: $Topic" -ForegroundColor White
    Write-Host "Mode: $(if ($Sequential) { 'Sequential' } else { 'Parallel' })" -ForegroundColor DarkGray
    Write-Host "Providers: $($Providers -join ', ')" -ForegroundColor DarkGray
    if ($FactCheck) { Write-Host "Fact-Check: Enabled (KB context loaded)" -ForegroundColor DarkGray }

    # Provider map - CLI-ONLY (no API keys needed)
    # Each CLI handles its own authentication
    $ProviderMap = @{
        "codex"  = { param($p) Invoke-CodexCLI -Prompt $p }   # OpenAI Codex CLI via WSL
        "gemini" = { param($p) Invoke-GeminiCLI -Prompt $p }  # Google Gemini CLI
        "claude" = { param($p) Invoke-ClaudeCLI -Prompt $p }  # Anthropic Claude CLI
    }

    $ProviderColors = @{
        "codex" = "Green"; "gemini" = "Blue"; "claude" = "Magenta"
    }

    # Expand "all" to all CLI providers
    if ($Providers -contains "all") {
        $Providers = @("codex", "gemini", "claude")
    }

    # Pre-flight check - ALL providers must be healthy before debate starts
    $healthResult = Test-ProviderHealth -Providers $Providers
    if ($null -eq $healthResult) {
        Write-Host "`n[ABORTED] Brainstorm cancelled - fix provider auth issues above and retry." -ForegroundColor Red
        return
    }
    $Providers = @($healthResult)
    Write-Host "All debaters ready: $($Providers -join ', ')" -ForegroundColor Green

    for ($round = 1; $round -le $Rounds; $round++) {
        Write-Host "`n--- Round $round ---" -ForegroundColor Yellow

        # Build context from previous rounds
        $context = Get-Content $sessionFile -Raw

        if ($Sequential) {
            # Sequential mode - each AI sees previous responses
            foreach ($provider in $Providers) {
                if (-not $ProviderMap.ContainsKey($provider)) {
                    Write-Host "  [!] Unknown provider: $provider" -ForegroundColor Red
                    continue
                }

                Write-Host "  [$provider] " -ForegroundColor $ProviderColors[$provider] -NoNewline
                Write-Host "Processing..." -ForegroundColor DarkGray

                $prompt = "Round $round discussion on: $Topic`n`n$kbContext`nPrevious context:`n$context`n`nProvide your analysis:"
                $response = Invoke-ProviderWithRetry -InvokeBlock $ProviderMap[$provider] -Prompt $prompt -ProviderName $provider

                Add-Content $sessionFile "`n### Round $round - $($provider.ToUpper())`n$response"
                $context = Get-Content $sessionFile -Raw

                Write-Host "  [$provider] " -ForegroundColor $ProviderColors[$provider] -NoNewline
                Write-Host "Done" -ForegroundColor Green
            }
        }
        else {
            # Parallel mode - run all providers simultaneously
            Write-Host "  [Running $($Providers.Count) providers in parallel...]" -ForegroundColor Cyan

            $jobs = @{}
            $tempFiles = @{}

            foreach ($provider in $Providers) {
                if (-not $ProviderMap.ContainsKey($provider)) { continue }

                $tempFile = Join-Path $OutputDir "${provider}_r${round}.tmp"
                $tempFiles[$provider] = $tempFile

                $prompt = "Round $round discussion on: $Topic`n`n$kbContext`nPrevious context:`n$context`n`nProvide your analysis:"

                # Start background job - CLI-only providers
                # Note: Jobs run in separate processes, need full paths to CLIs
                $npmBin = Join-Path $env:APPDATA "npm"
                $jobs[$provider] = Start-Job -ScriptBlock {
                    param($provider, $prompt, $outFile, $npmBin)

                    $result = switch ($provider) {
                        "codex" {
                            $tempIn = [System.IO.Path]::GetTempFileName()
                            $prompt | Set-Content $tempIn -Encoding UTF8 -NoNewline
                            $wslPath = wsl wslpath -u ($tempIn -replace '\\', '/')
                            $outputFile = "/tmp/codex-output-$([System.IO.Path]::GetRandomFileName()).txt"
                            $null = wsl bash -c "cat '$wslPath' | codex exec --skip-git-repo-check -o '$outputFile' - 2>/dev/null"
                            $out = wsl bash -c "cat '$outputFile' 2>/dev/null && rm -f '$outputFile'"
                            Remove-Item $tempIn -ErrorAction SilentlyContinue
                            if ($out -is [array]) { $out -join "`n" } else { $out }
                        }
                        "gemini" {
                            $tempIn = [System.IO.Path]::GetTempFileName()
                            $prompt | Set-Content $tempIn -Encoding UTF8 -NoNewline
                            $geminiCmd = Join-Path $npmBin "gemini.cmd"
                            $out = cmd /c "type `"$tempIn`" | `"$geminiCmd`" 2>nul"
                            Remove-Item $tempIn -ErrorAction SilentlyContinue
                            if ($out -is [array]) { $out -join "`n" } else { $out }
                        }
                        "claude" {
                            $prefixed = "IMPORTANT: Respond with text only. Do NOT use any tools.`n`n$prompt"
                            $tempIn = [System.IO.Path]::GetTempFileName()
                            $prefixed | Set-Content $tempIn -Encoding UTF8 -NoNewline
                            $claudeCmd = Join-Path $npmBin "claude.cmd"
                            $out = cmd /c "`"$claudeCmd`" --print < `"$tempIn`" 2>nul"
                            Remove-Item $tempIn -ErrorAction SilentlyContinue
                            if ($out -is [array]) { $out -join "`n" } else { $out }
                        }
                    }
                    if ($result) { $result | Set-Content $outFile -Encoding UTF8 }
                } -ArgumentList $provider, $prompt, $tempFile, $npmBin
            }

            # Wait for all jobs to complete
            if ($jobs.Count -gt 0) {
                $jobList = @($jobs.Values)
                $null = $jobList | Wait-Job -Timeout 300
            }

            # Collect responses (with fallback retry for empty ones)
            foreach ($provider in $Providers) {
                if (-not $jobs.ContainsKey($provider)) { continue }

                $tempFile = $tempFiles[$provider]
                $response = if (Test-Path $tempFile) {
                    Get-Content $tempFile -Raw
                } else {
                    $null
                }

                # If parallel job returned empty, retry synchronously
                if (-not $response -or $response.Trim() -eq '' -or $response -match '^\[No response') {
                    Write-Host "  [$provider] Empty parallel response, retrying synchronously..." -ForegroundColor Yellow
                    $retryPrompt = "Round $round discussion on: $Topic`n`n$kbContext`nPrevious context:`n$context`n`nProvide your analysis:"
                    $response = Invoke-ProviderWithRetry -InvokeBlock $ProviderMap[$provider] -Prompt $retryPrompt -ProviderName $provider
                }

                Add-Content $sessionFile "`n### Round $round - $($provider.ToUpper())`n$response"

                # Cleanup
                Remove-Job $jobs[$provider] -Force -ErrorAction SilentlyContinue
                Remove-Item $tempFile -ErrorAction SilentlyContinue

                Write-Host "  [$provider] " -ForegroundColor $ProviderColors[$provider] -NoNewline
                Write-Host "Done" -ForegroundColor Green
            }
        }
    }

    # Final consensus (use Claude CLI for synthesis)
    Write-Host "`n[Generating Consensus]" -ForegroundColor Magenta
    $finalContext = Get-Content $sessionFile -Raw
    $consensusPrompt = @"
You participated in this multi-AI discussion as one of the debaters.
Now, step back into a neutral synthesizer role.
Identify key agreements, disagreements, novel insights, and concrete action items.
Be concise but comprehensive. Flag any unresolved tensions.

$finalContext
"@
    $consensus = Invoke-ClaudeCLI -Prompt $consensusPrompt

    Add-Content $sessionFile "`n---`n## CONSENSUS`n$consensus"

    # Output formatting
    switch ($OutputFormat) {
        "json" {
            $jsonOutput = ConvertTo-BrainstormJSON -SessionFile $sessionFile
            $jsonFile = $sessionFile -replace '\.md$', '.json'
            $jsonOutput | Set-Content $jsonFile
            Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
        }
        "html" {
            $htmlOutput = ConvertTo-BrainstormHTML -SessionFile $sessionFile
            $htmlFile = $sessionFile -replace '\.md$', '.html'
            $htmlOutput | Set-Content $htmlFile
            Write-Host "`nHTML saved to: $htmlFile" -ForegroundColor Green
        }
        "slack" {
            if ($WebhookUrl) {
                Send-ToWebhook -SessionFile $sessionFile -WebhookUrl $WebhookUrl -Platform "slack"
            } else {
                Write-Err "Slack webhook URL required (-WebhookUrl)"
            }
        }
        "discord" {
            if ($WebhookUrl) {
                Send-ToWebhook -SessionFile $sessionFile -WebhookUrl $WebhookUrl -Platform "discord"
            } else {
                Write-Err "Discord webhook URL required (-WebhookUrl)"
            }
        }
    }

    # Post to GitHub if requested
    if ($PostResults -and ($PR -or $Issue)) {
        Post-BrainstormResult -SessionFile $sessionFile -PR $PR -Issue $Issue
    }

    # Copy to session.md as "latest" reference
    Copy-Item -Path $sessionFile -Destination $latestLink -Force

    Write-Host "`nSession saved to: $sessionFile" -ForegroundColor Green
    Write-Host "Latest session: $latestLink" -ForegroundColor DarkGray
    return $sessionFile
}

# ============================================================================
# GITHUB INTEGRATION FOR BRAINSTORM
# ============================================================================

function Get-GitHubBrainstormContext {
    param(
        [string]$PR,
        [string]$Issue
    )

    $context = ""

    if ($PR) {
        Write-Host "[+] Fetching PR #$PR context..." -ForegroundColor DarkGray
        try {
            $prData = gh pr view $PR --json title,body,files,comments 2>$null | ConvertFrom-Json
            $context += "### PR #${PR}: $($prData.title)`n"
            $context += "$($prData.body)`n`n"
            $context += "**Files changed:** $($prData.files.path -join ', ')`n`n"

            $diff = gh pr diff $PR 2>$null
            if ($diff) {
                # Limit diff to first 200 lines
                $diffLines = $diff -split "`n" | Select-Object -First 200
                $context += "**Diff (truncated):**`n``````diff`n$($diffLines -join "`n")`n```````n"
            }
        } catch {
            $context += "[Could not fetch PR context]`n"
        }
    }

    if ($Issue) {
        Write-Host "[+] Fetching Issue #$Issue context..." -ForegroundColor DarkGray
        try {
            $issueData = gh issue view $Issue --json title,body,comments 2>$null | ConvertFrom-Json
            $context += "### Issue #${Issue}: $($issueData.title)`n"
            $context += "$($issueData.body)`n"
        } catch {
            $context += "[Could not fetch Issue context]`n"
        }
    }

    return $context
}

function Post-BrainstormResult {
    param(
        [string]$SessionFile,
        [string]$PR,
        [string]$Issue
    )

    $content = Get-Content $SessionFile -Raw
    $consensusSection = ($content -split "## CONSENSUS")[-1].Trim()

    # Format as collapsible GitHub comment
    $comment = @"
## AI Brainstorm Analysis

<details>
<summary>Click to expand full session log</summary>

$content

</details>

### Summary
$consensusSection

---
*Generated by Multi-AI CLI Brainstorm*
"@

    if ($PR) {
        gh pr comment $PR --body $comment 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] Posted to PR #$PR" -ForegroundColor Green
        } else {
            Write-Err "Failed to post to PR #$PR"
        }
    }

    if ($Issue) {
        gh issue comment $Issue --body $comment 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] Posted to Issue #$Issue" -ForegroundColor Green
        } else {
            Write-Err "Failed to post to Issue #$Issue"
        }
    }
}

# ============================================================================
# OUTPUT FORMAT CONVERTERS
# ============================================================================

function ConvertTo-BrainstormJSON {
    param([string]$SessionFile)

    $content = Get-Content $SessionFile -Raw
    $rounds = @()

    # Parse markdown into structured data
    $sections = $content -split "### Round"
    foreach ($section in $sections | Select-Object -Skip 1) {
        if ($section -match "(\d+) - (\w+)\s*\n([\s\S]+?)(?=### Round|## CONSENSUS|$)") {
            $rounds += @{
                round = [int]$Matches[1]
                provider = $Matches[2]
                response = $Matches[3].Trim()
            }
        }
    }

    $consensus = ""
    if ($content -match "## CONSENSUS\s*\n([\s\S]+)$") {
        $consensus = $Matches[1].Trim()
    }

    return @{
        timestamp = (Get-Date -Format "o")
        rounds = $rounds
        consensus = $consensus
    } | ConvertTo-Json -Depth 10
}

function ConvertTo-BrainstormHTML {
    param([string]$SessionFile)

    $content = Get-Content $SessionFile -Raw

    # Simple markdown to HTML conversion
    $htmlContent = $content `
        -replace '### (.*)', '<h3>$1</h3>' `
        -replace '## (.*)', '<h2>$1</h2>' `
        -replace '# (.*)', '<h1>$1</h1>' `
        -replace '\*\*(.*?)\*\*', '<strong>$1</strong>' `
        -replace '```(\w*)\n([\s\S]*?)```', '<pre><code class="$1">$2</code></pre>' `
        -replace '\n\n', '</p><p>'

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AI Brainstorm Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 900px; margin: 0 auto; padding: 20px; line-height: 1.6; }
        h1 { color: #1a1a2e; border-bottom: 2px solid #4a4e69; }
        h2 { color: #22223b; margin-top: 2em; }
        h3 { color: #4a4e69; border-left: 3px solid #9a8c98; padding-left: 10px; }
        pre { background: #1e1e1e; color: #d4d4d4; padding: 15px; border-radius: 5px; overflow-x: auto; }
        code { font-family: 'Fira Code', 'Consolas', monospace; }
        .consensus { background: #f2e9e4; padding: 20px; border-radius: 8px; border-left: 4px solid #22223b; }
    </style>
</head>
<body>
<p>$htmlContent</p>
</body>
</html>
"@

    return $html
}

function Send-ToWebhook {
    param(
        [string]$SessionFile,
        [string]$WebhookUrl,
        [ValidateSet("slack", "discord")]
        [string]$Platform
    )

    $content = Get-Content $SessionFile -Raw
    $consensus = ""
    if ($content -match "## CONSENSUS\s*\n([\s\S]+)$") {
        $consensus = $Matches[1].Trim()
    }

    # Truncate for webhook limits
    if ($consensus.Length -gt 1500) {
        $consensus = $consensus.Substring(0, 1500) + "... [truncated]"
    }

    if ($Platform -eq "slack") {
        $payload = @{
            text = "AI Brainstorm Complete"
            blocks = @(
                @{ type = "header"; text = @{ type = "plain_text"; text = "AI Brainstorm Complete" } }
                @{ type = "section"; text = @{ type = "mrkdwn"; text = $consensus } }
            )
        }
    }
    else {  # Discord
        $payload = @{
            content = "**AI Brainstorm Complete**`n`n$consensus"
        }
    }

    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($payload | ConvertTo-Json -Depth 10) -ContentType "application/json"
        Write-Host "[+] Posted to $Platform" -ForegroundColor Green
    } catch {
        Write-Err "Failed to post to ${Platform}: $($_.Exception.Message)"
    }
}

# GitHub functions
function Get-GitHubNotes {
    param([int]$IssueNumber)

    if (-not $IssueNumber) {
        # Try to get from current branch PR
        $prJson = gh pr view --json number,title,body,comments 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Err "No issue number provided and no PR found for current branch"
            return
        }
        $pr = $prJson | ConvertFrom-Json
        $IssueNumber = $pr.number
    }

    Write-Host "`n📋 Notes for #$IssueNumber" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor DarkGray

    $comments = gh issue view $IssueNumber --json comments --jq '.comments[-5:]' 2>$null
    if ($LASTEXITCODE -ne 0) {
        $comments = gh pr view $IssueNumber --json comments --jq '.comments[-5:]' 2>$null
    }

    if ($comments) {
        $parsed = $comments | ConvertFrom-Json
        foreach ($c in $parsed) {
            $author = $c.author.login
            $body = $c.body

            # Highlight AI responses
            if ($body -match "### .* Claude|### .* GPT-4|### .* Gemini|### .* Grok") {
                Write-Host "`n[AI Response]" -ForegroundColor Yellow
            } else {
                Write-Host "`n[$author]:" -ForegroundColor Green
            }
            Write-Host $body.Substring(0, [Math]::Min(500, $body.Length))
            if ($body.Length -gt 500) { Write-Host "..." -ForegroundColor DarkGray }
        }
    } else {
        Write-Host "No comments found" -ForegroundColor DarkGray
    }
}

function Post-GitHubComment {
    param([int]$IssueNumber, [string]$Message)

    if (-not $IssueNumber -or -not $Message) {
        Write-Err "Usage: ai post [issue#] [message]"
        return
    }

    # Try issue first, then PR
    gh issue comment $IssueNumber --body $Message 2>$null
    if ($LASTEXITCODE -ne 0) {
        gh pr comment $IssueNumber --body $Message 2>$null
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Posted to #$IssueNumber" -ForegroundColor Green
    } else {
        Write-Err "Failed to post comment"
    }
}

function Post-AITag {
    param([int]$IssueNumber, [string]$AI, [string]$Message)

    if (-not $IssueNumber -or -not $AI -or -not $Message) {
        Write-Err "Usage: ai tag [issue#] [claude|gpt4|gemini|grok|all] [message]"
        return
    }

    $taggedMessage = "@ai:$AI $Message"
    Post-GitHubComment -IssueNumber $IssueNumber -Message $taggedMessage
}

# GitHub PR Review with Multi-AI Analysis
function Start-GitHubReview {
    param(
        [Parameter(Mandatory=$true)]
        [int]$PRNumber,
        [switch]$Post,
        [string[]]$Providers = @("codex", "gemini", "claude"),
        [string]$Focus = "general"
    )

    Write-Host "`n[GitHub Review] PR #$PRNumber" -ForegroundColor Cyan

    # Check gh CLI is available
    $ghVersion = gh --version 2>$null
    if (-not $ghVersion) {
        Write-Err "GitHub CLI (gh) not found. Install from https://cli.github.com"
        return
    }

    # Fetch PR metadata
    Write-Host "[1/5] Fetching PR metadata..." -ForegroundColor DarkGray
    $prJson = gh pr view $PRNumber --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,labels,reviewDecision 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to fetch PR #$PRNumber. Make sure you're in a git repo with gh authenticated."
        return
    }
    $pr = $prJson | ConvertFrom-Json

    # Fetch PR diff
    Write-Host "[2/5] Fetching PR diff..." -ForegroundColor DarkGray
    $diffRaw = gh pr diff $PRNumber 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to fetch diff for PR #$PRNumber"
        return
    }

    # Convert array to string (gh returns array of lines)
    if ($diffRaw -is [array]) {
        $diff = $diffRaw -join "`n"
    } else {
        $diff = $diffRaw
    }

    # Truncate diff if too long (keep first 6000 chars to leave room for prompt)
    $maxDiffLen = 6000
    if ($diff.Length -gt $maxDiffLen) {
        $diff = $diff.Substring(0, $maxDiffLen) + "`n... [diff truncated, $($diff.Length - $maxDiffLen) chars omitted]"
    }

    # Build context
    $prContext = @"
## Pull Request #$PRNumber
**Title:** $($pr.title)
**Author:** $($pr.author.login)
**Branch:** $($pr.headRefName) -> $($pr.baseRefName)
**Changes:** +$($pr.additions) -$($pr.deletions) in $($pr.changedFiles) files
**Labels:** $($pr.labels.name -join ', ')

### Description
$($pr.body)

### Diff
``````diff
$diff
``````
"@

    # Build review prompt based on focus
    $focusPrompts = @{
        "general" = "Perform a comprehensive code review covering correctness, style, performance, and maintainability."
        "security" = "Focus on security vulnerabilities: injection flaws, auth issues, data exposure, OWASP Top 10."
        "performance" = "Focus on performance: inefficient algorithms, N+1 queries, memory leaks, caching opportunities."
        "architecture" = "Focus on architecture: SOLID principles, separation of concerns, API design, scalability."
    }

    $reviewPrompt = @"
# Code Review Request

$prContext

## Review Instructions
$($focusPrompts[$Focus])

Provide your review in this format:
1. **Summary** - Brief overview of changes
2. **Issues Found** - List problems with severity (Critical/High/Medium/Low)
3. **Suggestions** - Improvements and best practices
4. **Questions** - Clarifications needed from author
5. **Verdict** - Approve / Request Changes / Needs Discussion
"@

    Write-Host "  (Prompt: $($reviewPrompt.Length) chars, Diff: $($diff.Length) chars)" -ForegroundColor DarkGray

    # Create notes directory
    $notesDir = ".ai-notes/github/pr"
    if (-not (Test-Path $notesDir)) {
        New-Item -ItemType Directory -Force -Path $notesDir | Out-Null
    }

    # Run multi-AI review
    Write-Host "[3/5] Running multi-AI review..." -ForegroundColor DarkGray
    $reviews = @{}
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    foreach ($provider in $Providers) {
        Write-Host "  [$provider] " -NoNewline -ForegroundColor $(switch ($provider) {
            "codex" { "Green" }
            "gemini" { "Blue" }
            "claude" { "Magenta" }
            default { "White" }
        })

        $startTime = Get-Date
        $response = switch ($provider) {
            "codex" { Invoke-CodexCLI -Prompt $reviewPrompt }
            "gemini" { Invoke-GeminiCLI -Prompt $reviewPrompt }
            "claude" { Invoke-ClaudeCLI -Prompt $reviewPrompt }
        }
        $elapsed = ((Get-Date) - $startTime).TotalSeconds

        # Debug: show response info
        $respLen = if ($response) { $response.Length } else { 0 }
        Write-Host "Done ($([math]::Round($elapsed, 1))s, $respLen chars)" -ForegroundColor DarkGray

        $reviews[$provider] = $response
    }

    # Build reviews section string (foreach doesn't work in here-strings)
    $reviewsSection = ""
    foreach ($provider in $reviews.Keys) {
        # Truncate each review to 2000 chars for synthesis to avoid prompt overflow
        $reviewText = $reviews[$provider]
        if ($reviewText.Length -gt 2000) {
            $reviewText = $reviewText.Substring(0, 2000) + "... [truncated]"
        }
        $reviewsSection += "## $($provider.ToUpper()) Review`n$reviewText`n`n"
    }

    # Generate synthesis (only if multiple reviewers, otherwise just use the single review)
    $synthesis = ""
    if ($reviews.Count -gt 1) {
        Write-Host "[4/5] Synthesizing reviews..." -ForegroundColor DarkGray
        $synthesisPrompt = @"
Synthesize these AI code reviews for PR #$PRNumber into a brief consolidated summary:

$reviewsSection

Provide:
1. **Key Issues** (by severity)
2. **Verdict** (Approve/Request Changes)
3. **Top 3 Action Items**

Be brief (under 500 words).
"@
        $synthesis = Invoke-ClaudeCLI -Prompt $synthesisPrompt
    } else {
        Write-Host "[4/5] Single reviewer - using review as summary..." -ForegroundColor DarkGray
        # Extract key points from the single review
        $firstKey = $reviews.Keys | Select-Object -First 1
        $singleReview = $reviews[$firstKey]
        if ($singleReview.Length -gt 1500) {
            $synthesis = $singleReview.Substring(0, 1500) + "..."
        } else {
            $synthesis = $singleReview
        }
    }

    # Build individual reviews section for report
    $individualReviews = ""
    foreach ($provider in $reviews.Keys) {
        $individualReviews += "### $($provider.ToUpper())`n$($reviews[$provider])`n`n"
    }

    # Build final report
    $report = @"
# AI Code Review: PR #$PRNumber
**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Focus:** $Focus
**Reviewers:** $($Providers -join ', ')

---

## Consolidated Review

$synthesis

---

## Individual Reviews

$individualReviews

---
*Generated by Multi-AI CLI v1.0*
"@

    # Save to notes
    $notesFile = Join-Path $notesDir "pr-$PRNumber-$timestamp.md"
    $report | Set-Content $notesFile -Encoding UTF8
    Write-Host "[5/5] Review saved to $notesFile" -ForegroundColor DarkGray

    # Display summary
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "REVIEW SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $synthesis -ForegroundColor White

    # Post to GitHub if requested
    if ($Post) {
        Write-Host "`n[Posting to GitHub...]" -ForegroundColor Yellow

        $commentBody = @"
## AI Code Review

$synthesis

---
<details>
<summary>View individual AI reviews</summary>

$individualReviews

</details>

*Generated by Multi-AI Orchestrator*
"@

        gh pr comment $PRNumber --body $commentBody 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Review posted to PR #$PRNumber" -ForegroundColor Green
        } else {
            Write-Err "Failed to post review comment"
        }
    }

    return @{
        PRNumber = $PRNumber
        Reviews = $reviews
        Synthesis = $synthesis
        NotesFile = $notesFile
    }
}

# GitHub Issue Triage with Multi-AI Analysis
function Start-GitHubTriage {
    param(
        [Parameter(Mandatory=$true)]
        [int]$IssueNumber,
        [switch]$Post,
        [string[]]$Providers = @("gemini", "claude"),
        [switch]$FindPRs
    )

    Write-Host "`n[GitHub Triage] Issue #$IssueNumber" -ForegroundColor Cyan

    # Check gh CLI is available
    $ghVersion = gh --version 2>$null
    if (-not $ghVersion) {
        Write-Err "GitHub CLI (gh) not found. Install from https://cli.github.com"
        return
    }

    # Fetch issue metadata
    Write-Host "[1/5] Fetching issue..." -ForegroundColor DarkGray
    $issueJson = gh issue view $IssueNumber --json title,body,author,labels,assignees,state,comments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to fetch issue #$IssueNumber"
        return
    }
    $issue = $issueJson | ConvertFrom-Json

    # Build issue context
    $commentsText = ""
    if ($issue.comments) {
        $recentComments = $issue.comments | Select-Object -Last 5
        foreach ($c in $recentComments) {
            $commentsText += "**$($c.author.login):** $($c.body)`n`n"
        }
    }

    $issueContext = @"
## Issue #$IssueNumber
**Title:** $($issue.title)
**Author:** $($issue.author.login)
**State:** $($issue.state)
**Labels:** $($issue.labels.name -join ', ')
**Assignees:** $($issue.assignees.login -join ', ')

### Description
$($issue.body)

### Recent Comments
$commentsText
"@

    # Find related PRs if requested
    $relatedPRs = ""
    if ($FindPRs) {
        Write-Host "[2/5] Finding related PRs..." -ForegroundColor DarkGray
        $prs = gh pr list --json number,title,headRefName --limit 10 2>$null | ConvertFrom-Json
        if ($prs) {
            $relatedPRs = "`n### Related PRs`n"
            foreach ($pr in $prs) {
                $relatedPRs += "- PR #$($pr.number): $($pr.title) ($($pr.headRefName))`n"
            }
        }
    } else {
        Write-Host "[2/5] Skipping PR search..." -ForegroundColor DarkGray
    }

    # Build triage prompt
    $triagePrompt = @"
# Issue Triage Request

$issueContext
$relatedPRs

## Triage Instructions
Analyze this GitHub issue and provide:

1. **Category** - Bug / Feature Request / Question / Documentation / Security
2. **Priority** - Critical / High / Medium / Low
3. **Complexity** - Simple / Moderate / Complex
4. **Affected Areas** - Which parts of the codebase might be involved
5. **Suggested Labels** - Recommend labels to add
6. **Suggested Assignee** - Type of expertise needed
7. **Next Steps** - Recommended actions
8. **Related Issues** - If this seems like a duplicate or related to common patterns

Be concise and actionable.
"@

    # Create notes directory
    $notesDir = ".ai-notes/github/issues"
    if (-not (Test-Path $notesDir)) {
        New-Item -ItemType Directory -Force -Path $notesDir | Out-Null
    }

    # Run multi-AI triage
    Write-Host "[3/5] Running multi-AI triage..." -ForegroundColor DarkGray
    $triages = @{}
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    foreach ($provider in $Providers) {
        Write-Host "  [$provider] " -NoNewline -ForegroundColor $(switch ($provider) {
            "codex" { "Green" }
            "gemini" { "Blue" }
            "claude" { "Magenta" }
            default { "White" }
        })

        $startTime = Get-Date
        $response = switch ($provider) {
            "codex" { Invoke-CodexCLI -Prompt $triagePrompt }
            "gemini" { Invoke-GeminiCLI -Prompt $triagePrompt }
            "claude" { Invoke-ClaudeCLI -Prompt $triagePrompt }
        }
        $elapsed = ((Get-Date) - $startTime).TotalSeconds

        Write-Host "Done ($([math]::Round($elapsed, 1))s)" -ForegroundColor DarkGray
        $triages[$provider] = $response
    }

    # Build summary (use first triage or synthesize if multiple)
    Write-Host "[4/5] Building summary..." -ForegroundColor DarkGray
    $summary = ""
    if ($triages.Count -eq 1) {
        $firstKey = $triages.Keys | Select-Object -First 1
        $summary = $triages[$firstKey]
    } else {
        # Quick consensus extraction
        $triageTexts = ""
        foreach ($provider in $triages.Keys) {
            $text = $triages[$provider]
            if ($text.Length -gt 1500) { $text = $text.Substring(0, 1500) + "..." }
            $triageTexts += "## $($provider.ToUpper())`n$text`n`n"
        }
        $consensusPrompt = "Merge these triage analyses into one brief summary with Category, Priority, Complexity, and Next Steps:`n`n$triageTexts"
        $summary = Invoke-ClaudeCLI -Prompt $consensusPrompt
    }

    # Build individual triages section
    $individualTriages = ""
    foreach ($provider in $triages.Keys) {
        $individualTriages += "### $($provider.ToUpper())`n$($triages[$provider])`n`n"
    }

    # Build final report
    $report = @"
# AI Issue Triage: Issue #$IssueNumber
**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Analyzers:** $($Providers -join ', ')

---

## Triage Summary

$summary

---

## Individual Analyses

$individualTriages

---
*Generated by Multi-AI CLI v1.0*
"@

    # Save to notes
    $notesFile = Join-Path $notesDir "issue-$IssueNumber-$timestamp.md"
    $report | Set-Content $notesFile -Encoding UTF8
    Write-Host "[5/5] Triage saved to $notesFile" -ForegroundColor DarkGray

    # Display summary
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "TRIAGE SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $summary -ForegroundColor White

    # Post to GitHub if requested
    if ($Post) {
        Write-Host "`n[Posting to GitHub...]" -ForegroundColor Yellow

        $commentBody = @"
## AI Issue Triage

$summary

---
*Generated by Multi-AI Orchestrator*
"@

        gh issue comment $IssueNumber --body $commentBody 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Posted triage to issue #$IssueNumber" -ForegroundColor Green
        } else {
            Write-Err "Failed to post triage comment"
        }
    }

    return @{
        IssueNumber = $IssueNumber
        Triages = $triages
        Summary = $summary
        NotesFile = $notesFile
    }
}

# Show help
function Show-Help {
    Write-Host @"

  Multi-AI CLI
  ============

  QUERY AN AI (API-based):
    ai claude "your question"     Ask Claude (architecture focus)
    ai gpt4 "your question"       Ask GPT-4 (code quality focus)
    ai gemini "your question"     Ask Gemini (security focus)
    ai grok "your question"       Ask Grok (edge cases focus)
    ai all "your question"        Ask all 4 AIs in sequence

  BRAINSTORM (CLI-based, no API keys needed):
    ai brainstorm "topic"                    Multi-AI discussion (Codex + Gemini)
    ai brainstorm -Rounds 5 "topic"          Custom number of rounds
    ai brainstorm -Sequential "topic"        Back-and-forth debate mode
    ai brainstorm -Providers codex,claude "topic"   Choose providers
    ai brainstorm -PR 123 "security review"  Include PR context
    ai brainstorm -PostResults "topic"       Post results to GitHub
    ai brainstorm -FactCheck "topic"         Enable KB context (checks decisions.md)

  PRESETS (35+ specialized prompts):
    ai presets                    List all available presets
    ai preset threat "code"       Run threat model (-> Gemini)
    ai preset coderev "changes"   Multi-AI code review (-> Brainstorm)
    ai preset testplan "feature"  Generate test plan (-> GPT-4)
    ai -Preset security "code"    Alternative syntax with flag

  WITH CONTEXT (auto-includes repo info):
    ai claude -Context "review"   Include git status, diff, README
    ai context                    Show current repo context

  PIPE INPUT:
    cat file.py | ai claude "review this"
    git diff | ai -Preset risk    Pipe to preset

  GITHUB PR REVIEW (multi-AI code review):
    ai gh-review <PR#>            Review a pull request with all AIs
    ai gh-review <PR#> -Post      Review and post comment to PR
    ai gh-review <PR#> -Focus security   Security-focused review
    ai gh-review <PR#> -Providers gemini,claude   Choose reviewers

  GITHUB ISSUE TRIAGE (multi-AI analysis):
    ai gh-triage <issue#>         Triage an issue (category, priority, next steps)
    ai gh-triage <issue#> -Post   Triage and post comment to issue
    ai gh-triage <issue#> -FindPRs   Include related PR analysis

  YAML ORCHESTRATION (Brainstorming as Code):
    ai orchestrate run <file.yml>      Run a YAML orchestration spec
    ai orchestrate validate <file.yml> Validate YAML against schema
    ai orchestrate new <name>          Create new orchestration from template
    ai orchestrate list                List available templates

  GITHUB INTEGRATION:
    ai notes [issue#]             Show recent comments (last 5)
    ai post [issue#] "message"    Post a comment
    ai tag [issue#] claude "msg"  Post @ai:claude tag

  EXAMPLES:
    ai brainstorm "review auth module security"
    ai brainstorm -PR 42 -PostResults "full review"
    ai preset coderev "<file contents>"
    git diff | ai brainstorm "review these changes"

  SETUP (for API-based commands):
    Set environment variables or create scripts/.env:
      ANTHROPIC_API_KEY=sk-ant-...
      OPENAI_API_KEY=sk-...
      GOOGLE_API_KEY=...
      XAI_API_KEY=...

  CLI REQUIREMENTS (for brainstorm):
    - codex CLI in WSL (run: codex login)
    - gemini CLI (run: gemini auth)
    - claude CLI (already authenticated)

"@ -ForegroundColor Cyan
}

# Main logic
$prompt = $Args -join " "

# Filter out -Context from args if present inline
$prompt = $prompt -replace '-Context\s*', ''

# Check for piped input
if (-not [Console]::IsInputRedirected -eq $false) {
    $pipedInput = $input | Out-String
    if ($pipedInput) {
        $prompt = "$prompt`n`n$pipedInput"
    }
}

# Add repo context if -Context flag is set
if ($Context) {
    Write-Host "[+] Including repo context..." -ForegroundColor DarkGray
    $repoContext = Get-RepoContext
    $prompt = "REPO CONTEXT:`n$repoContext`n`nQUESTION/TASK:`n$prompt"
}

# Handle -Preset flag
if ($Preset) {
    if (-not $Presets[$Preset]) {
        Write-Err "Unknown preset: $Preset"
        Write-Host "Run 'ai presets' to see available presets" -ForegroundColor DarkGray
        exit 1
    }

    $p = $Presets[$Preset]
    # Use $Command and $Args as the user input when -Preset is used
    $userInput = @($Command) + $Args | Where-Object { $_ } | ForEach-Object { $_.Trim() }
    $userInput = $userInput -join " "
    $fullPrompt = "$($p.prompt)`n`nCODE/CONTEXT:`n$userInput"

    Write-Host "[Preset: $($p.name)] -> $($p.ai)" -ForegroundColor Cyan

    switch ($p.ai) {
        "claude" {
            Write-AI "[C]" "Claude" "Magenta"
            $result = Invoke-Claude -Prompt $fullPrompt
            if ($result) { Write-Response $result }
        }
        "gpt4" {
            Write-AI "[G]" "GPT-4" "Green"
            $result = Invoke-GPT4 -Prompt $fullPrompt
            if ($result) { Write-Response $result }
        }
        "gemini" {
            Write-AI "[S]" "Gemini" "Blue"
            $result = Invoke-Gemini -Prompt $fullPrompt
            if ($result) { Write-Response $result }
        }
        "grok" {
            Write-AI "[X]" "Grok" "Red"
            $result = Invoke-Grok -Prompt $fullPrompt
            if ($result) { Write-Response $result }
        }
        "all" {
            Write-AI "[C]" "Claude" "Magenta"
            $claude = Invoke-Claude -Prompt $fullPrompt
            if ($claude) { Write-Response $claude }

            Write-AI "[G]" "GPT-4" "Green"
            $gpt4 = Invoke-GPT4 -Prompt $fullPrompt
            if ($gpt4) { Write-Response $gpt4 }

            Write-AI "[S]" "Gemini" "Blue"
            $gemini = Invoke-Gemini -Prompt $fullPrompt
            if ($gemini) { Write-Response $gemini }

            Write-AI "[X]" "Grok" "Red"
            $grok = Invoke-Grok -Prompt $fullPrompt
            if ($grok) { Write-Response $grok }
        }
    }
    exit 0
}

switch ($Command.ToLower()) {
    "brainstorm" {
        # Parse brainstorm arguments
        $brainstormArgs = @{
            Topic = $Args -join " "
        }

        # Check for flags in Args
        for ($i = 0; $i -lt $Args.Count; $i++) {
            switch ($Args[$i]) {
                "-Rounds" { $brainstormArgs.Rounds = [int]$Args[++$i] }
                "-Sequential" { $brainstormArgs.Sequential = $true }
                "-Providers" { $brainstormArgs.Providers = ($Args[++$i] -split '[,\s]+' | Where-Object { $_ -ne '' }) }
                "-PR" { $brainstormArgs.PR = $Args[++$i] }
                "-Issue" { $brainstormArgs.Issue = $Args[++$i] }
                "-PostResults" { $brainstormArgs.PostResults = $true }
                "-OutputFormat" { $brainstormArgs.OutputFormat = $Args[++$i] }
                "-WebhookUrl" { $brainstormArgs.WebhookUrl = $Args[++$i] }
                "-OutputDir" { $brainstormArgs.OutputDir = $Args[++$i] }
                "-FactCheck" { $brainstormArgs.FactCheck = $true }
            }
        }

        # Remove flag values from topic
        # Flags that consume the next argument (have a value)
        $valuedFlags = @("-Rounds", "-Providers", "-PR", "-Issue", "-OutputFormat", "-WebhookUrl", "-OutputDir")
        # Switch flags (-Sequential, -PostResults, -FactCheck) have no value - don't skip next arg

        $topic = @()
        $skipNext = $false
        foreach ($arg in $Args) {
            if ($skipNext) { $skipNext = $false; continue }
            if ($arg -match '^-') {
                if ($arg -in $valuedFlags) { $skipNext = $true }
                continue
            }
            $topic += $arg
        }
        $brainstormArgs.Topic = $topic -join " "

        if (-not $brainstormArgs.Topic) {
            Write-Host "Usage: ai brainstorm <topic> [-Rounds N] [-Sequential] [-Providers codex,gemini,claude]" -ForegroundColor Yellow
            Write-Host "       ai brainstorm -PR 123 'security review'" -ForegroundColor DarkGray
            Write-Host "       ai brainstorm -Providers all 'full review'" -ForegroundColor DarkGray
            exit 1
        }

        Start-AIBrainstorm @brainstormArgs
    }
    "context" {
        Show-Context
    }
    "claude" {
        Write-AI "brain" "Claude" "Magenta"
        $result = Invoke-Claude -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "gpt4" {
        Write-AI "computer" "GPT-4" "Green"
        $result = Invoke-GPT4 -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "gemini" {
        Write-AI "lock" "Gemini" "Blue"
        $result = Invoke-Gemini -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "grok" {
        Write-AI "[X]" "Grok" "Red"
        $result = Invoke-Grok -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "all" {
        Write-Host "`n[*] Asking All AIs..." -ForegroundColor Cyan

        Write-AI "[C]" "Claude" "Magenta"
        $claude = Invoke-Claude -Prompt $prompt
        if ($claude) { Write-Response $claude }

        Write-AI "[G]" "GPT-4" "Green"
        $gpt4 = Invoke-GPT4 -Prompt $prompt
        if ($gpt4) { Write-Response $gpt4 }

        Write-AI "[S]" "Gemini" "Blue"
        $gemini = Invoke-Gemini -Prompt $prompt
        if ($gemini) { Write-Response $gemini }

        Write-AI "[X]" "Grok" "Red"
        $grok = Invoke-Grok -Prompt $prompt
        if ($grok) { Write-Response $grok }
    }
    "notes" {
        $issueNum = if ($Args[0]) { [int]$Args[0] } else { $null }
        Get-GitHubNotes -IssueNumber $issueNum
    }
    "post" {
        $issueNum = [int]$Args[0]
        $message = ($Args | Select-Object -Skip 1) -join " "
        Post-GitHubComment -IssueNumber $issueNum -Message $message
    }
    "tag" {
        $issueNum = [int]$Args[0]
        $ai = $Args[1]
        $message = ($Args | Select-Object -Skip 2) -join " "
        Post-AITag -IssueNumber $issueNum -AI $ai -Message $message
    }
    "presets" {
        Show-Presets
    }
    "gh-review" {
        # Parse gh-review arguments
        $prNum = $null
        $postResults = $false
        $providers = @("codex", "gemini", "claude")
        $focus = "general"

        for ($i = 0; $i -lt $Args.Count; $i++) {
            switch ($Args[$i]) {
                "-Post" { $postResults = $true }
                "-Providers" {
                    $nextArg = $Args[++$i]
                    # Handle both array and string inputs
                    # PowerShell converts "a,b,c" to "a b c" when passed as args
                    if ($nextArg -is [array]) {
                        $providers = $nextArg
                    } else {
                        # Split on comma or space
                        $providers = $nextArg -split '[,\s]+' | Where-Object { $_ -ne '' }
                    }
                }
                "-Focus" { $focus = $Args[++$i] }
                default {
                    if ($Args[$i] -match '^\d+$') {
                        $prNum = [int]$Args[$i]
                    }
                }
            }
        }

        if (-not $prNum) {
            Write-Host "Usage: ai gh-review <PR#> [-Post] [-Providers codex,gemini,claude] [-Focus general|security|performance|architecture]" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Examples:" -ForegroundColor DarkGray
            Write-Host "  ai gh-review 123                    Review PR #123" -ForegroundColor DarkGray
            Write-Host "  ai gh-review 123 -Post              Review and post comment to PR" -ForegroundColor DarkGray
            Write-Host "  ai gh-review 123 -Focus security    Security-focused review" -ForegroundColor DarkGray
            Write-Host "  ai gh-review 123 -Providers gemini  Use only Gemini" -ForegroundColor DarkGray
            exit 1
        }

        Start-GitHubReview -PRNumber $prNum -Post:$postResults -Providers $providers -Focus $focus
    }
    "gh-triage" {
        # Parse gh-triage arguments
        $issueNum = $null
        $postResults = $false
        $providers = @("gemini", "claude")
        $findPRs = $false

        for ($i = 0; $i -lt $Args.Count; $i++) {
            switch ($Args[$i]) {
                "-Post" { $postResults = $true }
                "-Providers" { $providers = ($Args[++$i] -split '[,\s]+' | Where-Object { $_ -ne '' }) }
                "-FindPRs" { $findPRs = $true }
                default {
                    if ($Args[$i] -match '^\d+$') {
                        $issueNum = [int]$Args[$i]
                    }
                }
            }
        }

        if (-not $issueNum) {
            Write-Host "Usage: ai gh-triage <issue#> [-Post] [-Providers gemini,claude] [-FindPRs]" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Examples:" -ForegroundColor DarkGray
            Write-Host "  ai gh-triage 42                     Triage issue #42" -ForegroundColor DarkGray
            Write-Host "  ai gh-triage 42 -Post               Triage and post comment" -ForegroundColor DarkGray
            Write-Host "  ai gh-triage 42 -FindPRs            Include related PRs" -ForegroundColor DarkGray
            exit 1
        }

        Start-GitHubTriage -IssueNumber $issueNum -Post:$postResults -Providers $providers -FindPRs:$findPRs
    }
    "preset" {
        $presetName = $Args[0]
        $userInput = ($Args | Select-Object -Skip 1) -join " "

        if (-not $presetName -or -not $Presets[$presetName]) {
            Write-Err "Unknown preset: $presetName"
            Write-Host "Run 'ai presets' to see available presets" -ForegroundColor DarkGray
            return
        }

        $p = $Presets[$presetName]
        $fullPrompt = "$($p.prompt)`n`nCODE/CONTEXT:`n$userInput"

        Write-Host "[Preset: $($p.name)] -> $($p.ai)" -ForegroundColor Cyan

        switch ($p.ai) {
            "claude" {
                Write-AI "[C]" "Claude" "Magenta"
                $result = Invoke-Claude -Prompt $fullPrompt
                if ($result) { Write-Response $result }
            }
            "gpt4" {
                Write-AI "[G]" "GPT-4" "Green"
                $result = Invoke-GPT4 -Prompt $fullPrompt
                if ($result) { Write-Response $result }
            }
            "gemini" {
                Write-AI "[S]" "Gemini" "Blue"
                $result = Invoke-Gemini -Prompt $fullPrompt
                if ($result) { Write-Response $result }
            }
            "grok" {
                Write-AI "[X]" "Grok" "Red"
                $result = Invoke-Grok -Prompt $fullPrompt
                if ($result) { Write-Response $result }
            }
            "all" {
                Write-AI "[C]" "Claude" "Magenta"
                $claude = Invoke-Claude -Prompt $fullPrompt
                if ($claude) { Write-Response $claude }

                Write-AI "[G]" "GPT-4" "Green"
                $gpt4 = Invoke-GPT4 -Prompt $fullPrompt
                if ($gpt4) { Write-Response $gpt4 }

                Write-AI "[S]" "Gemini" "Blue"
                $gemini = Invoke-Gemini -Prompt $fullPrompt
                if ($gemini) { Write-Response $gemini }

                Write-AI "[X]" "Grok" "Red"
                $grok = Invoke-Grok -Prompt $fullPrompt
                if ($grok) { Write-Response $grok }
            }
        }
    }
    "orchestrate" {
        $orchestratePath = Join-Path $PSScriptRoot "orchestrate.ps1"
        if (-not (Test-Path $orchestratePath)) {
            Write-Err "orchestrate.ps1 not found at $orchestratePath"
            exit 1
        }
        # Pass subcommand and remaining args to orchestrate.ps1
        $subCmd = if ($Args[0]) { $Args[0] } else { "help" }
        $subArgs = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }
        & $orchestratePath -Command $subCmd -Target ($subArgs -join " ")
    }
    { $_ -in "help", "-h", "--help", "" } {
        Show-Help
    }
    default {
        Write-Err "Unknown command: $Command"
        Show-Help
    }
}
