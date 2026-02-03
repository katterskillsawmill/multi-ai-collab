<#
.SYNOPSIS
    Multi-AI Code Review Pipeline - Local CLI Version

.DESCRIPTION
    Orchestrates Claude Code, Gemini CLI, and GitHub Copilot for comprehensive code review.
    Runs all AI reviews in parallel and consolidates results.

.PARAMETER Path
    Path to file or directory to review

.PARAMETER PR
    GitHub PR number to review (alternative to Path)

.PARAMETER Output
    Output format: console, markdown, or json

.EXAMPLE
    .\multi-ai-review.ps1 -Path "lib/services/social_service.dart"
    .\multi-ai-review.ps1 -PR 123
    .\multi-ai-review.ps1 -Path "lib/" -Output markdown > review.md
#>

param(
    [string]$Path,
    [int]$PR,
    [ValidateSet("console", "markdown", "json")]
    [string]$Output = "console"
)

$ErrorActionPreference = "Stop"

# Colors for console output
function Write-Header { param($text) Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Success { param($text) Write-Host $text -ForegroundColor Green }
function Write-Warning { param($text) Write-Host $text -ForegroundColor Yellow }
function Write-Error { param($text) Write-Host $text -ForegroundColor Red }

# Get content to review
function Get-ReviewContent {
    if ($PR) {
        Write-Header "Fetching PR #$PR diff"
        $diff = gh pr diff $PR 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get PR diff: $diff"
        }
        return $diff
    }
    elseif ($Path) {
        if (Test-Path $Path -PathType Container) {
            Write-Header "Reading directory: $Path"
            $files = Get-ChildItem -Path $Path -Recurse -Include "*.dart" |
                     Select-Object -First 10  # Limit for API constraints
            $content = ""
            foreach ($file in $files) {
                $content += "`n--- $($file.FullName) ---`n"
                $content += Get-Content $file.FullName -Raw
            }
            return $content
        }
        else {
            Write-Header "Reading file: $Path"
            return Get-Content $Path -Raw
        }
    }
    else {
        throw "Specify either -Path or -PR parameter"
    }
}

# Run Claude Code review
function Invoke-ClaudeReview {
    param($content)
    Write-Header "Running Claude Code Review (Architecture)"

    $prompt = @"
Review this code for architectural concerns:
1. Design patterns and SOLID principles
2. Scalability issues
3. Security vulnerabilities
4. Performance implications

Format with severity: 🔴 Critical, 🟡 Warning, 🟢 Suggestion

Code:
$content
"@

    # Use Claude Code CLI if available, otherwise API
    try {
        $result = echo $prompt | claude --print 2>&1
        return $result
    }
    catch {
        Write-Warning "Claude CLI not available, skipping..."
        return "Claude review skipped - CLI not installed"
    }
}

# Run Gemini review
function Invoke-GeminiReview {
    param($content)
    Write-Header "Running Gemini Review (Security & Docs)"

    $prompt = @"
Review this code for security and documentation:
1. Security vulnerabilities (OWASP Top 10)
2. Missing documentation
3. Input validation issues
4. Sensitive data exposure

Format with severity: 🔴 Critical, 🟡 Warning, 🟢 Suggestion

Code:
$content
"@

    try {
        # Check for Gemini CLI
        $geminiPath = Get-Command gemini -ErrorAction SilentlyContinue
        if ($geminiPath) {
            $result = echo $prompt | gemini 2>&1
            return $result
        }
        else {
            Write-Warning "Gemini CLI not available, skipping..."
            return "Gemini review skipped - CLI not installed"
        }
    }
    catch {
        Write-Warning "Gemini review failed: $_"
        return "Gemini review failed"
    }
}

# Run GitHub Copilot review
function Invoke-CopilotReview {
    param($content)
    Write-Header "Running GitHub Copilot Review (Code Quality)"

    try {
        # Check for gh copilot extension
        $copilotCheck = gh copilot --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $prompt = "Review this code for quality, best practices, and potential bugs: $content"
            $result = gh copilot suggest "$prompt" 2>&1
            return $result
        }
        else {
            Write-Warning "GitHub Copilot CLI not available, skipping..."
            return "Copilot review skipped - extension not installed"
        }
    }
    catch {
        Write-Warning "Copilot review failed: $_"
        return "Copilot review failed"
    }
}

# Main execution
try {
    Write-Host "`n🤖 Multi-AI Code Review Pipeline" -ForegroundColor Magenta
    Write-Host "=================================" -ForegroundColor Magenta

    $content = Get-ReviewContent

    # Truncate if too long
    if ($content.Length -gt 50000) {
        Write-Warning "Content truncated to 50,000 characters for API limits"
        $content = $content.Substring(0, 50000)
    }

    # Run reviews (could be parallelized with Start-Job)
    $claudeResult = Invoke-ClaudeReview -content $content
    $geminiResult = Invoke-GeminiReview -content $content
    $copilotResult = Invoke-CopilotReview -content $content

    # Output results
    switch ($Output) {
        "markdown" {
            @"
# 🤖 Multi-AI Code Review

## 🧠 Claude (Architecture & Design)
$claudeResult

---

## 🔒 Gemini (Security & Documentation)
$geminiResult

---

## 💻 GitHub Copilot (Code Quality)
$copilotResult

---

*Generated by Multi-AI Review Pipeline*
"@
        }
        "json" {
            @{
                claude = $claudeResult
                gemini = $geminiResult
                copilot = $copilotResult
                timestamp = Get-Date -Format "o"
            } | ConvertTo-Json -Depth 10
        }
        default {
            Write-Header "Claude Review Results"
            Write-Host $claudeResult

            Write-Header "Gemini Review Results"
            Write-Host $geminiResult

            Write-Header "Copilot Review Results"
            Write-Host $copilotResult

            Write-Success "`n✅ Multi-AI review complete!"
        }
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}
