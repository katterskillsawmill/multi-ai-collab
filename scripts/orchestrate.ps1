<#
.SYNOPSIS
    YAML-Driven Multi-AI Orchestrator v1.0
    "Brainstorming as Code" (BaC) Framework

.DESCRIPTION
    orchestrate run <file.yml>         - Run a YAML orchestration spec
    orchestrate validate <file.yml>    - Validate YAML against schema
    orchestrate new <name>             - Create new orchestration from template
    orchestrate list                   - List available templates

.EXAMPLE
    orchestrate run brainstorm.yml
    orchestrate new security-review
    orchestrate validate my-session.yml
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("run", "validate", "new", "list", "help")]
    [string]$Command = "help",

    [Parameter(Position=1)]
    [string]$Target,

    [Parameter(Position=2, ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

$ScriptDir = $PSScriptRoot
$SchemasDir = Join-Path $ScriptDir "schemas"
$TemplatesDir = Join-Path $ScriptDir "templates"

# Ensure directories exist
@($SchemasDir, $TemplatesDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Force -Path $_ | Out-Null
    }
}

# Load .env file
$EnvFile = Join-Path $ScriptDir ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

# Import powershell-yaml module or use simple parser
function ConvertFrom-YamlSimple {
    param([string]$Content)

    # YAML parser for orchestration specs
    $result = @{}
    $lines = $Content -split "`n"

    function Get-Indent($line) {
        $count = 0
        foreach ($char in $line.ToCharArray()) {
            if ($char -eq ' ') { $count++ }
            else { break }
        }
        return $count
    }

    function Parse-Value($val) {
        $clean = $val.Trim().Trim('"', "'")
        if ($clean -match '^\d+$') { return [int]$clean }
        if ($clean -eq 'true') { return $true }
        if ($clean -eq 'false') { return $false }
        if ($clean -match '^\[(.+)\]$') {
            return @(($matches[1] -split ',') | ForEach-Object { $_.Trim().Trim('"', "'") })
        }
        return $clean
    }

    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        $trimmed = $line.Trim()

        # Skip empty/comments
        if (-not $trimmed -or $trimmed.StartsWith('#')) { $i++; continue }

        $indent = Get-Indent $line

        # Top-level section
        if ($indent -eq 0 -and $trimmed -match '^(\w+[-\w]*):\s*(.*)$') {
            $sectionKey = $matches[1]
            $sectionValue = $matches[2].Trim()

            if ($sectionValue) {
                # Inline value at top level
                $result[$sectionKey] = Parse-Value $sectionValue
                $i++
                continue
            }

            # Section with nested content
            $i++
            $sectionData = @{}
            $sectionList = [System.Collections.ArrayList]@()
            $isList = $false

            while ($i -lt $lines.Count) {
                $subLine = $lines[$i]
                $subTrimmed = $subLine.Trim()

                # Skip empty/comments
                if (-not $subTrimmed -or $subTrimmed.StartsWith('#')) { $i++; continue }

                $subIndent = Get-Indent $subLine

                # Back to top level - don't increment, let outer loop handle
                if ($subIndent -eq 0) { break }

                # List item
                if ($subTrimmed.StartsWith('-')) {
                    $isList = $true
                    $listContent = $subTrimmed.Substring(1).Trim()
                    $listIndent = $subIndent

                    # List item with inline key-value
                    if ($listContent -match '^(\w+[-\w]*):\s*(.*)$') {
                        $itemObj = @{}
                        $itemObj[$matches[1]] = Parse-Value $matches[2]
                        $i++

                        # Collect additional fields for this list item
                        while ($i -lt $lines.Count) {
                            $itemLine = $lines[$i]
                            $itemTrimmed = $itemLine.Trim()

                            if (-not $itemTrimmed -or $itemTrimmed.StartsWith('#')) { $i++; continue }

                            $itemIndent = Get-Indent $itemLine

                            # Back to list level or higher
                            if ($itemIndent -le $listIndent) { break }

                            # Field of list item
                            if ($itemTrimmed -match '^(\w+[-\w]*):\s*(.*)$') {
                                $fieldKey = $matches[1]
                                $fieldVal = $matches[2].Trim()

                                # Multi-line string
                                if ($fieldVal -eq '|') {
                                    $mlLines = @()
                                    $mlBaseIndent = $itemIndent + 2
                                    $i++
                                    while ($i -lt $lines.Count) {
                                        $mlLine = $lines[$i]
                                        $mlIndent = Get-Indent $mlLine
                                        if ($mlIndent -ge $mlBaseIndent -or $mlLine.Trim() -eq '') {
                                            if ($mlLine.Length -gt $mlBaseIndent) {
                                                $mlLines += $mlLine.Substring($mlBaseIndent)
                                            } else {
                                                $mlLines += ""
                                            }
                                            $i++
                                        } else {
                                            break
                                        }
                                    }
                                    $itemObj[$fieldKey] = ($mlLines -join "`n").TrimEnd()
                                    continue
                                }

                                $itemObj[$fieldKey] = Parse-Value $fieldVal
                            }
                            $i++
                        }
                        $null = $sectionList.Add($itemObj)
                    } else {
                        # Simple list item (just a value)
                        $null = $sectionList.Add((Parse-Value $listContent))
                        $i++
                    }
                    continue
                }

                # Regular nested key-value
                if ($subTrimmed -match '^(\w+[-\w]*):\s*(.*)$') {
                    $sectionData[$matches[1]] = Parse-Value $matches[2]
                }
                $i++
            }

            $result[$sectionKey] = if ($isList) { ,@($sectionList.ToArray()) } else { $sectionData }
            continue
        }

        $i++
    }

    return $result
}

function Read-YamlSpec {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        throw "YAML file not found: $FilePath"
    }

    $content = Get-Content $FilePath -Raw

    # Try to use powershell-yaml if available
    try {
        if (Get-Module -ListAvailable -Name powershell-yaml) {
            Import-Module powershell-yaml -ErrorAction Stop
            return ConvertFrom-Yaml $content
        }
    } catch {}

    # Fallback to simple parser
    return ConvertFrom-YamlSimple -Content $content
}

function Test-YamlSchema {
    param(
        [hashtable]$Spec,
        [string]$SchemaPath
    )

    $errors = @()

    # Required top-level fields
    if (-not $Spec.spec) {
        $errors += "Missing required section: 'spec'"
    } else {
        if (-not $Spec.spec.topic) {
            $errors += "Missing required field: spec.topic"
        }
        if (-not $Spec.spec.providers) {
            $errors += "Missing required field: spec.providers"
        }
    }

    if (-not $Spec.phases) {
        $errors += "Missing required section: 'phases'"
    }

    # Validate phases
    if ($Spec.phases -is [array]) {
        foreach ($phase in $Spec.phases) {
            if (-not $phase.name) {
                $errors += "Phase missing required field: 'name'"
            }
            if (-not $phase.prompt) {
                $errors += "Phase '$($phase.name)' missing required field: 'prompt'"
            }
        }
    }

    return @{
        Valid = ($errors.Count -eq 0)
        Errors = $errors
    }
}

# AI Invocation Functions (from ai.ps1)
function Invoke-CodexCLI {
    param([string]$Prompt)

    try {
        # Write prompt to temp file
        $tempFile = [System.IO.Path]::GetTempFileName()
        $Prompt | Set-Content $tempFile -Encoding UTF8 -NoNewline
        $wslPath = wsl wslpath -u ($tempFile -replace '\\', '/')

        # Use -o to capture output to file, --skip-git-repo-check for non-repo contexts
        $outputFile = "/tmp/codex-output-$([System.IO.Path]::GetRandomFileName()).txt"
        $null = wsl bash -c "cat '$wslPath' | codex exec --skip-git-repo-check -o '$outputFile' - 2>/dev/null"

        # Read the output file
        $result = wsl bash -c "cat '$outputFile' 2>/dev/null && rm -f '$outputFile'"

        Remove-Item $tempFile -ErrorAction SilentlyContinue

        if ($result -is [array]) {
            return ($result -join "`n")
        }
        return $result
    } catch {
        return "[Codex error: $($_.Exception.Message)]"
    }
}

function Invoke-GeminiCLI {
    param([string]$Prompt)

    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $Prompt | Set-Content $tempFile -Encoding UTF8 -NoNewline

        # Use full path to gemini CLI (npm global bin)
        $npmBin = Join-Path $env:APPDATA "npm"
        $geminiCmd = Join-Path $npmBin "gemini.cmd"

        $result = cmd /c "type `"$tempFile`" | `"$geminiCmd`" 2>nul"
        Remove-Item $tempFile -ErrorAction SilentlyContinue

        if ($result -is [array]) {
            return ($result -join "`n")
        }
        return $result
    } catch {
        return "[Gemini error: $($_.Exception.Message)]"
    }
}

function Invoke-ClaudeCLI {
    param([string]$Prompt)

    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $Prompt | Set-Content $tempFile -Encoding UTF8 -NoNewline

        # Use full path to claude CLI (npm global bin)
        $npmBin = Join-Path $env:APPDATA "npm"
        $claudeCmd = Join-Path $npmBin "claude.cmd"

        $result = cmd /c "`"$claudeCmd`" --print < `"$tempFile`" 2>nul"
        Remove-Item $tempFile -ErrorAction SilentlyContinue

        if ($result -is [array]) {
            return ($result -join "`n")
        }
        return $result
    } catch {
        return "[Claude error: $($_.Exception.Message)]"
    }
}

function Invoke-Provider {
    param(
        [string]$Provider,
        [string]$Prompt
    )

    switch ($Provider.ToLower()) {
        "codex"  { return Invoke-CodexCLI -Prompt $Prompt }
        "gemini" { return Invoke-GeminiCLI -Prompt $Prompt }
        "claude" { return Invoke-ClaudeCLI -Prompt $Prompt }
        default  { return "[Unknown provider: $Provider]" }
    }
}

function Start-Orchestration {
    param(
        [string]$YamlPath
    )

    Write-Host "`n[Orchestrator] Loading spec: $YamlPath" -ForegroundColor Cyan

    # Parse YAML
    $spec = Read-YamlSpec -FilePath $YamlPath

    # Validate
    $validation = Test-YamlSchema -Spec $spec
    if (-not $validation.Valid) {
        Write-Host "[Orchestrator] Validation failed:" -ForegroundColor Red
        $validation.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        return
    }

    Write-Host "[Orchestrator] Spec validated successfully" -ForegroundColor Green

    # Extract config
    $topic = $spec.spec.topic
    $providers = $spec.spec.providers
    $rounds = if ($spec.spec.rounds) { $spec.spec.rounds } else { 1 }

    # Setup output
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputDir = if ($spec.output -and $spec.output.dir) { $spec.output.dir } else { ".ai-orchestrate" }
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    $sessionFile = Join-Path $outputDir "session-$timestamp.md"
    $jsonFile = Join-Path $outputDir "decision_brief-$timestamp.json"

    # Initialize session
    @"
# AI Orchestration Session
**Started:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Topic:** $topic
**Providers:** $($providers -join ', ')
**Rounds:** $rounds

---
"@ | Set-Content $sessionFile

    Write-Host "`n[Orchestrator] Session started" -ForegroundColor Cyan
    Write-Host "  Topic: $topic" -ForegroundColor White
    Write-Host "  Providers: $($providers -join ', ')" -ForegroundColor White
    Write-Host "  Output: $sessionFile" -ForegroundColor DarkGray

    # Context stack for accumulating responses
    $contextStack = @{
        topic = $topic
        rounds = @()
        phases = @()
    }

    # Run phases
    $phases = $spec.phases
    if (-not $phases) {
        # Default single-phase if none specified
        $phases = @(
            @{ name = "discuss"; prompt = "Discuss the topic thoroughly." }
        )
    }

    foreach ($phase in $phases) {
        $phaseName = $phase.name
        $phasePrompt = $phase.prompt

        Write-Host "`n========== PHASE: $($phaseName.ToUpper()) ==========" -ForegroundColor Yellow
        Add-Content $sessionFile "`n## Phase: $phaseName`n"

        $phaseResults = @{
            name = $phaseName
            responses = @{}
        }

        for ($round = 1; $round -le $rounds; $round++) {
            Write-Host "`n--- Round $round of $rounds ---" -ForegroundColor Cyan
            Add-Content $sessionFile "`n### Round $round`n"

            $roundResults = @{}

            # Build context from previous rounds
            $contextText = Get-Content $sessionFile -Raw

            foreach ($provider in $providers) {
                Write-Host "[$provider] " -ForegroundColor $(switch ($provider) {
                    "codex" { "Green" }
                    "gemini" { "Blue" }
                    "claude" { "Magenta" }
                    default { "White" }
                }) -NoNewline

                $fullPrompt = @"
# AI Brainstorming Session
Topic: $topic
Phase: $phaseName
Round: $round of $rounds

## Instructions
$phasePrompt

Think deeply and provide thorough analysis. Be specific and actionable.

## Previous Context
$contextText

## Your Response
Provide your analysis for this phase:
"@

                $startTime = Get-Date
                $response = Invoke-Provider -Provider $provider -Prompt $fullPrompt
                $elapsed = ((Get-Date) - $startTime).TotalSeconds

                Write-Host "Done ($([math]::Round($elapsed, 1))s)" -ForegroundColor DarkGray

                # Log to session
                Add-Content $sessionFile "`n#### $($provider.ToUpper())`n$response`n"

                $roundResults[$provider] = $response
            }

            $contextStack.rounds += @{
                round = $round
                phase = $phaseName
                results = $roundResults
            }
        }

        $contextStack.phases += $phaseResults
    }

    # Generate consensus/synthesis
    Write-Host "`n========== SYNTHESIZING ==========" -ForegroundColor Magenta

    $synthesisPrompt = @"
# Synthesis Request

Based on this multi-AI discussion session, provide a comprehensive synthesis:

$(Get-Content $sessionFile -Raw)

## Generate:
1. **Key Agreements** - Points all AIs agreed on
2. **Key Differences** - Notable divergent perspectives
3. **Top Recommendations** - Ranked by consensus strength
4. **Action Items** - Concrete next steps
5. **Open Questions** - Unresolved issues needing human input

Format as a clear, actionable decision brief.
"@

    $synthesis = Invoke-ClaudeCLI -Prompt $synthesisPrompt

    Add-Content $sessionFile "`n---`n## SYNTHESIS`n$synthesis"

    # Generate JSON output
    $jsonOutput = @{
        timestamp = (Get-Date -Format "o")
        topic = $topic
        providers = $providers
        rounds = $rounds
        context = $contextStack
        synthesis = $synthesis
    } | ConvertTo-Json -Depth 10

    $jsonOutput | Set-Content $jsonFile -Encoding UTF8

    # Generate decision brief markdown
    $briefFile = Join-Path $outputDir "decision_brief-$timestamp.md"
    @"
# Decision Brief
**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Topic:** $topic

---

$synthesis

---
*Generated by Multi-AI Orchestrator v1.0*
"@ | Set-Content $briefFile

    Write-Host "`n[Orchestrator] Session complete!" -ForegroundColor Green
    Write-Host "  Session log: $sessionFile" -ForegroundColor White
    Write-Host "  Decision brief: $briefFile" -ForegroundColor White
    Write-Host "  JSON export: $jsonFile" -ForegroundColor White

    return @{
        SessionFile = $sessionFile
        BriefFile = $briefFile
        JsonFile = $jsonFile
        Context = $contextStack
        Synthesis = $synthesis
    }
}

function New-OrchestrationSpec {
    param([string]$Name)

    $templatePath = Join-Path $TemplatesDir "brainstorm.yml"

    if (-not (Test-Path $templatePath)) {
        Write-Host "[Orchestrator] Default template not found. Creating..." -ForegroundColor Yellow
        # Template will be created separately
    }

    $newPath = "$Name.yml"

    if (Test-Path $newPath) {
        Write-Host "[Orchestrator] File already exists: $newPath" -ForegroundColor Red
        return
    }

    Copy-Item $templatePath $newPath
    Write-Host "[Orchestrator] Created: $newPath" -ForegroundColor Green
    Write-Host "Edit the file to customize your orchestration spec." -ForegroundColor DarkGray
}

function Show-Templates {
    Write-Host "`n[Orchestrator] Available Templates:" -ForegroundColor Cyan

    $templates = Get-ChildItem $TemplatesDir -Filter "*.yml" -ErrorAction SilentlyContinue

    if ($templates) {
        $templates | ForEach-Object {
            Write-Host "  - $($_.BaseName)" -ForegroundColor White
        }
    } else {
        Write-Host "  (no templates found)" -ForegroundColor DarkGray
    }

    Write-Host "`nUse 'orchestrate new <name>' to create from template." -ForegroundColor DarkGray
}

function Show-Help {
    Write-Host @"

Multi-AI Orchestrator v1.0 - "Brainstorming as Code"
====================================================

COMMANDS:
  run <file.yml>       Run an orchestration spec
  validate <file.yml>  Validate YAML against schema
  new <name>           Create new spec from template
  list                 List available templates
  help                 Show this help

EXAMPLES:
  orchestrate run brainstorm.yml
  orchestrate new security-review
  orchestrate validate my-session.yml

YAML SPEC FORMAT:
  spec:
    topic: "Your topic here"
    providers: [codex, gemini, claude]
    rounds: 3

  phases:
    - name: diverge
      prompt: "Generate 3 novel ideas..."
    - name: synthesize
      prompt: "Merge into recommendations..."

  output:
    dir: ".ai-orchestrate"

"@ -ForegroundColor White
}

# Main command router
switch ($Command) {
    "run" {
        if (-not $Target) {
            Write-Host "[Orchestrator] Error: Specify a YAML file to run" -ForegroundColor Red
            Write-Host "Usage: orchestrate run <file.yml>" -ForegroundColor DarkGray
            return
        }
        Start-Orchestration -YamlPath $Target
    }
    "validate" {
        if (-not $Target) {
            Write-Host "[Orchestrator] Error: Specify a YAML file to validate" -ForegroundColor Red
            return
        }
        $spec = Read-YamlSpec -FilePath $Target
        $result = Test-YamlSchema -Spec $spec
        if ($result.Valid) {
            Write-Host "[Orchestrator] Valid!" -ForegroundColor Green
        } else {
            Write-Host "[Orchestrator] Invalid:" -ForegroundColor Red
            $result.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
    }
    "new" {
        if (-not $Target) {
            Write-Host "[Orchestrator] Error: Specify a name for the new spec" -ForegroundColor Red
            return
        }
        New-OrchestrationSpec -Name $Target
    }
    "list" {
        Show-Templates
    }
    "help" {
        Show-Help
    }
    default {
        Show-Help
    }
}
