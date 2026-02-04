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

.EXAMPLE
    ai claude "Review this code for architectural issues"
    ai notes 42
    ai tag 42 gpt4 "What patterns would improve this?"
#>

param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Args
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

# Colors
function Write-AI { param($icon, $name, $color) Write-Host "`n$icon " -NoNewline; Write-Host $name -ForegroundColor $color }
function Write-Response { param($text) Write-Host $text -ForegroundColor White }
function Write-Err { param($msg) Write-Host "ERROR: $msg" -ForegroundColor Red }

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
            if ($body -match "### 🧠 Claude|### 💻 GPT-4|### 🔒 Gemini|### 🚀 Grok") {
                Write-Host "`n🤖 AI Response:" -ForegroundColor Yellow
            } else {
                Write-Host "`n👤 $author`:" -ForegroundColor Green
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
        Write-Err "Usage: ai post <issue#> `"message`""
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
        Write-Err "Usage: ai tag <issue#> <claude|gpt4|gemini|grok|all> `"message`""
        return
    }

    $taggedMessage = "@ai:$AI $Message"
    Post-GitHubComment -IssueNumber $IssueNumber -Message $taggedMessage
}

# Show help
function Show-Help {
    Write-Host @"

  Multi-AI CLI
  ============

  QUERY AN AI:
    ai claude "your question"     Ask Claude (architecture focus)
    ai gpt4 "your question"       Ask GPT-4 (code quality focus)
    ai gemini "your question"     Ask Gemini (security focus)
    ai grok "your question"       Ask Grok (edge cases focus)
    ai all "your question"        Ask all 4 AIs in sequence

  PIPE INPUT:
    cat file.py | ai claude "review this"
    git diff | ai gpt4 "check for bugs"

  GITHUB INTEGRATION:
    ai notes [issue#]             Show recent comments (last 5)
    ai post <issue#> "message"    Post a comment
    ai tag <issue#> claude "msg"  Post @ai:claude tag to trigger workflow

  EXAMPLES:
    ai claude "What's the best architecture for a chat app?"
    ai notes 42
    ai tag 42 gemini "Check this for security issues"
    git diff HEAD~1 | ai all "Review these changes"

  SETUP:
    Set environment variables or create scripts/.env:
      ANTHROPIC_API_KEY=sk-ant-...
      OPENAI_API_KEY=sk-...
      GOOGLE_API_KEY=...
      XAI_API_KEY=...

"@ -ForegroundColor Cyan
}

# Main logic
$prompt = $Args -join " "

# Check for piped input
if (-not [Console]::IsInputRedirected -eq $false) {
    $pipedInput = $input | Out-String
    if ($pipedInput) {
        $prompt = "$prompt`n`n$pipedInput"
    }
}

switch ($Command.ToLower()) {
    "claude" {
        Write-AI "🧠" "Claude" "Magenta"
        $result = Invoke-Claude -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "gpt4" {
        Write-AI "💻" "GPT-4" "Green"
        $result = Invoke-GPT4 -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "gemini" {
        Write-AI "🔒" "Gemini" "Blue"
        $result = Invoke-Gemini -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "grok" {
        Write-AI "🚀" "Grok" "Red"
        $result = Invoke-Grok -Prompt $prompt
        if ($result) { Write-Response $result }
    }
    "all" {
        Write-Host "`n🤖 Asking All AIs..." -ForegroundColor Cyan

        Write-AI "🧠" "Claude" "Magenta"
        $claude = Invoke-Claude -Prompt $prompt
        if ($claude) { Write-Response $claude }

        Write-AI "💻" "GPT-4" "Green"
        $gpt4 = Invoke-GPT4 -Prompt $prompt
        if ($gpt4) { Write-Response $gpt4 }

        Write-AI "🔒" "Gemini" "Blue"
        $gemini = Invoke-Gemini -Prompt $prompt
        if ($gemini) { Write-Response $gemini }

        Write-AI "🚀" "Grok" "Red"
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
    { $_ -in "help", "-h", "--help", "" } {
        Show-Help
    }
    default {
        Write-Err "Unknown command: $Command"
        Show-Help
    }
}
