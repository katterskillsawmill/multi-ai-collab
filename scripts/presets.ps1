<#
.SYNOPSIS
    AI Preset Prompts - Quick commands for common tasks

.DESCRIPTION
    Productivity presets for Claude, Codex, Gemini CLI workflows

.EXAMPLE
    preset review          # Code review current changes
    preset arch            # Architecture review
    preset security        # Security audit
    preset test            # Generate tests
    preset docs            # Generate documentation
    preset refactor        # Suggest refactoring
    preset debug           # Debug help
    preset explain         # Explain code
#>

param(
    [Parameter(Position=0)]
    [string]$Preset,

    [Parameter(Position=1)]
    [string]$Target,

    [Parameter(Position=2, ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

# Preset definitions
$Presets = @{
    # CODE REVIEW
    review = @{
        name = "Code Review"
        prompt = "Review this code for bugs, edge cases, and improvements. Be specific about line numbers and provide fixed code."
        ai = "all"
    }

    quick = @{
        name = "Quick Review"
        prompt = "Quick review - only mention critical issues or bugs. Skip style/formatting."
        ai = "gpt4"
    }

    # ARCHITECTURE
    arch = @{
        name = "Architecture Review"
        prompt = "Analyze the architecture. Identify: 1) Design pattern issues 2) Scalability concerns 3) Coupling problems 4) Suggested improvements"
        ai = "claude"
    }

    design = @{
        name = "Design Patterns"
        prompt = "What design patterns are used here? Are they appropriate? What patterns would improve this code?"
        ai = "claude"
    }

    # SECURITY
    security = @{
        name = "Security Audit"
        prompt = "Security audit: Check for OWASP Top 10, injection vulnerabilities, auth issues, data exposure, input validation. List each issue with severity."
        ai = "gemini"
    }

    secrets = @{
        name = "Secrets Check"
        prompt = "Scan for hardcoded secrets, API keys, passwords, tokens, credentials. List any found with line numbers."
        ai = "gemini"
    }

    # TESTING
    test = @{
        name = "Generate Tests"
        prompt = "Generate comprehensive unit tests for this code. Include edge cases, error conditions, and happy paths. Use appropriate testing framework."
        ai = "gpt4"
    }

    testcases = @{
        name = "Test Cases"
        prompt = "List all test cases needed for this code. Include: unit tests, integration tests, edge cases, error scenarios. Don't write code, just list cases."
        ai = "grok"
    }

    # DOCUMENTATION
    docs = @{
        name = "Generate Docs"
        prompt = "Generate documentation: function signatures, parameter descriptions, return values, usage examples. Use appropriate doc format (JSDoc, docstrings, etc.)"
        ai = "gpt4"
    }

    readme = @{
        name = "README"
        prompt = "Generate a README.md with: description, installation, usage examples, API reference, configuration options."
        ai = "gpt4"
    }

    # REFACTORING
    refactor = @{
        name = "Refactor"
        prompt = "Suggest refactoring improvements: extract methods, reduce complexity, improve naming, apply SOLID principles. Show before/after."
        ai = "claude"
    }

    simplify = @{
        name = "Simplify"
        prompt = "Simplify this code. Remove unnecessary complexity, consolidate logic, improve readability. Show the simplified version."
        ai = "claude"
    }

    dry = @{
        name = "DRY Check"
        prompt = "Find duplicated code and logic. Suggest how to DRY (Don't Repeat Yourself) it up with shared functions/utilities."
        ai = "gpt4"
    }

    # DEBUGGING
    debug = @{
        name = "Debug Help"
        prompt = "Analyze this code/error. Identify the root cause, explain why it happens, and provide the fix."
        ai = "gpt4"
    }

    trace = @{
        name = "Trace Execution"
        prompt = "Trace through this code step by step. Show variable values at each step. Identify where things go wrong."
        ai = "claude"
    }

    # EXPLANATION
    explain = @{
        name = "Explain Code"
        prompt = "Explain this code in detail: what it does, how it works, why design decisions were made. Suitable for a junior developer."
        ai = "claude"
    }

    eli5 = @{
        name = "ELI5"
        prompt = "Explain this code like I'm 5. Use simple analogies, no jargon."
        ai = "grok"
    }

    # EDGE CASES
    edge = @{
        name = "Edge Cases"
        prompt = "What edge cases could break this code? Consider: null/undefined, empty inputs, large inputs, concurrent access, network failures, type mismatches."
        ai = "grok"
    }

    break = @{
        name = "Try to Break It"
        prompt = "Act as a QA engineer trying to break this code. What inputs, conditions, or scenarios would cause failures? Be creative and adversarial."
        ai = "grok"
    }

    # PERFORMANCE
    perf = @{
        name = "Performance"
        prompt = "Analyze performance: time complexity, space complexity, bottlenecks, optimization opportunities. Suggest improvements."
        ai = "claude"
    }

    # GIT/PR
    commit = @{
        name = "Commit Message"
        prompt = "Write a concise, conventional commit message for these changes. Format: type(scope): description"
        ai = "gpt4"
    }

    pr = @{
        name = "PR Description"
        prompt = "Write a PR description: summary of changes, motivation, testing done, breaking changes, related issues."
        ai = "gpt4"
    }

    # FLUTTER SPECIFIC
    flutter = @{
        name = "Flutter Review"
        prompt = "Review this Flutter/Dart code for: widget tree efficiency, state management, memory leaks, platform-specific issues, accessibility."
        ai = "claude"
    }

    riverpod = @{
        name = "Riverpod Review"
        prompt = "Review Riverpod usage: provider organization, state management patterns, ref usage, disposal, testing patterns."
        ai = "claude"
    }

    # MULTI-AI COLLABORATION
    collab = @{
        name = "Full AI Review"
        prompt = "Comprehensive review covering: architecture (Claude), code quality (GPT-4), security (Gemini), edge cases (Grok)."
        ai = "all"
    }

    # RISK ANALYSIS (Codex suggested)
    risk = @{
        name = "Risk Summary"
        prompt = "Summarize risks of this change: 1) What could go wrong? 2) Severity of each risk (Critical/High/Medium/Low) 3) Top 3 mitigations. Be specific about failure scenarios."
        ai = "all"
    }

    regression = @{
        name = "Regression Hunt"
        prompt = "What previously-working behavior might this change break? Consider: existing features, integrations, backwards compatibility, user expectations. List specific scenarios."
        ai = "grok"
    }

    # TEST PLANNING
    testplan = @{
        name = "Test Plan Builder"
        prompt = "Generate a concrete test plan with: 1) Test titles 2) Test data/inputs 3) Expected outcomes 4) Edge cases to cover. Format as a checklist."
        ai = "gpt4"
    }

    # THREAT MODELING
    threat = @{
        name = "Threat Model"
        prompt = "Security threat model: 1) Enumerate attack surfaces 2) List abuse cases 3) Identify trust boundaries 4) Suggest mitigations. Use STRIDE or similar framework."
        ai = "gemini"
    }

    # COMPATIBILITY
    compat = @{
        name = "Compatibility Check"
        prompt = "List possible breaking changes for: 1) Older configurations 2) Different environments (dev/staging/prod) 3) Runtime versions 4) API consumers. Include migration steps if needed."
        ai = "claude"
    }

    # STRUCTURED OUTPUT
    structured = @{
        name = "Structured Review"
        prompt = "Review and output findings in this format for each issue:
| Severity | Area | File | Finding | Recommendation |
Use: CRITICAL (must fix), WARNING (should fix), SUGGESTION (nice to have), INFO (note)"
        ai = "all"
    }
}

function Show-Presets {
    Write-Host "`nAvailable Presets" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor DarkGray

    $categories = @{
        "CODE REVIEW" = @("review", "quick", "structured")
        "ARCHITECTURE" = @("arch", "design")
        "SECURITY" = @("security", "secrets", "threat")
        "TESTING" = @("test", "testcases", "testplan")
        "DOCUMENTATION" = @("docs", "readme")
        "REFACTORING" = @("refactor", "simplify", "dry")
        "DEBUGGING" = @("debug", "trace")
        "EXPLANATION" = @("explain", "eli5")
        "EDGE CASES" = @("edge", "break", "regression")
        "PERFORMANCE" = @("perf")
        "RISK ANALYSIS" = @("risk", "compat")
        "GIT/PR" = @("commit", "pr")
        "FLUTTER" = @("flutter", "riverpod")
        "MULTI-AI" = @("collab")
    }

    foreach ($cat in $categories.Keys) {
        Write-Host "`n$cat" -ForegroundColor Yellow
        foreach ($key in $categories[$cat]) {
            if ($Presets.ContainsKey($key)) {
                $p = $Presets[$key]
                $aiIcon = switch ($p.ai) {
                    "claude" { "[C]" }
                    "gpt4" { "[G]" }
                    "gemini" { "[S]" }
                    "grok" { "[X]" }
                    "all" { "[*]" }
                }
                Write-Host "  $aiIcon " -NoNewline
                Write-Host $key.PadRight(12) -NoNewline -ForegroundColor Green
                Write-Host $p.name -ForegroundColor White
            }
        }
    }

    Write-Host "`nUsage:" -ForegroundColor Cyan
    Write-Host "  preset <name>              Use with clipboard content"
    Write-Host "  preset <name> <file>       Use with file content"
    Write-Host "  git diff | preset review   Pipe input"
    Write-Host ""
}

function Invoke-Preset {
    param($PresetName, $Input)

    if (-not $Presets.ContainsKey($PresetName)) {
        Write-Host "Unknown preset: $PresetName" -ForegroundColor Red
        Show-Presets
        return
    }

    $p = $Presets[$PresetName]
    $fullPrompt = "$($p.prompt)`n`n$Input"

    Write-Host "`n[>] $($p.name)" -ForegroundColor Cyan

    # Route to appropriate AI
    $scriptDir = $PSScriptRoot
    & "$scriptDir\ai.ps1" $p.ai $fullPrompt
}

# Main - only run when executed directly, not when sourced
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Preset -or $Preset -in @("help", "-h", "--help", "list")) {
        Show-Presets
        exit
    }

    # Get input
    $inputContent = ""

    # Check for piped input
    if ($input) {
        $inputContent = $input | Out-String
    }

    # Check for file argument
    if ($Target -and (Test-Path $Target)) {
        $inputContent = Get-Content $Target -Raw
    }

    # Check clipboard if no other input
    if (-not $inputContent) {
        $inputContent = Get-Clipboard
        if ($inputContent) {
            Write-Host "[Clipboard] Using clipboard content" -ForegroundColor DarkGray
        }
    }

    if (-not $inputContent) {
        Write-Host "No input provided. Copy code to clipboard, specify a file, or pipe input." -ForegroundColor Yellow
        exit
    }

    Invoke-Preset -PresetName $Preset -Input $inputContent
}
