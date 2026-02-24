<#
.SYNOPSIS
    Knowledge Base Functions for AI Orchestration

.DESCRIPTION
    Provides functions for querying decisions.md, session history,
    and checking for conflicts during brainstorm debates.

    Dot-source this file in ai.ps1:
    . (Join-Path $PSScriptRoot "kb-functions.ps1")
#>

# Configuration
$script:KBConfig = @{
    # Master (Orchestrator) KB
    NotesDir = Join-Path $PSScriptRoot ".ai-notes"
    DecisionsFile = "decisions.md"
    SessionIndex = "session_index.json"
    SprintFile = "rufus-90day-sprint.md"
    RoadmapFile = "rufus-vision-roadmap.md"
}

# Projects Registry - Maps project names to their KB locations
$script:ProjectRegistry = @{
    "master" = @{
        Name = "AI Orchestrator (Master)"
        NotesDir = Join-Path $PSScriptRoot ".ai-notes"
        DecisionsFile = "decisions.md"
        SessionIndex = "session_index.json"
    }
    "rufus" = @{
        Name = "Rufus Flutter App (ARCHIVED)"
        NotesDir = "C:\Users\dcoop\.claude-worktrees\rufus-flutter-app\musing-kowalevski\.ai-notes"
        DecisionsFile = "rufus-decisions.md"
        SessionIndex = "rufus-session-index.json"
        SprintFile = "MVP_SPRINT_90_DAY.md"
        RoadmapFile = "VISION_MASTER_PLAN.md"
        TechArchFile = "TECH_ARCHITECTURE.md"
        Status = "Archived - Tenant #2 for later"
    }
    "dogapp" = @{
        Name = "Dog Show Education App (PRIMARY)"
        NotesDir = "C:\Users\dcoop\dog-show-app\.ai-notes"
        DecisionsFile = "dog-app-decisions.md"
        SessionIndex = "dog-app-session-index.json"
        SprintFile = "MVP_SPRINT_6_WEEK.md"
        RoadmapFile = "DOG_APP_ROADMAP.md"
        Status = "Active - Primary Development Focus"
    }
}

function Get-ProjectConfig {
    <#
    .SYNOPSIS
        Get KB configuration for a specific project
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [string]$Project = "master"
    )

    $projectLower = $Project.ToLower()

    if ($script:ProjectRegistry.ContainsKey($projectLower)) {
        return $script:ProjectRegistry[$projectLower]
    }

    Write-Warning "Project '$Project' not found in registry. Using master KB."
    return $script:ProjectRegistry["master"]
}

function Get-RegisteredProjects {
    <#
    .SYNOPSIS
        List all registered projects
    #>
    return $script:ProjectRegistry.Keys | ForEach-Object {
        [PSCustomObject]@{
            Key = $_
            Name = $script:ProjectRegistry[$_].Name
            NotesDir = $script:ProjectRegistry[$_].NotesDir
        }
    }
}

# ============================================================================
# DECISIONS PARSING
# ============================================================================

function Get-LockedDecisions {
    <#
    .SYNOPSIS
        Get all locked decisions from decisions.md
    .PARAMETER Category
        Optional filter by category (e.g., "Tech Stack", "Platform Strategy")
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [string]$Category,
        [string]$Project = "master"
    )

    $config = Get-ProjectConfig -Project $Project
    $filePath = Join-Path $config.NotesDir $config.DecisionsFile
    if (-not (Test-Path $filePath)) {
        Write-Warning "Decisions file not found: $filePath"
        return @()
    }

    $content = Get-Content $filePath -Raw
    $decisions = @()

    # Find LOCKED DECISIONS section
    if ($content -match '## LOCKED DECISIONS([\s\S]*?)(?=## TENTATIVE|## DEPRECATED|$)') {
        $lockedSection = $Matches[1]

        # Parse each category table
        $categoryMatches = [regex]::Matches($lockedSection, '### ([^\n]+)\n\|[^\n]+\n\|[-| ]+\n((?:\|[^\n]+\n)*)')

        foreach ($match in $categoryMatches) {
            $categoryName = $match.Groups[1].Value.Trim()

            # Skip if category filter specified and doesn't match
            if ($Category -and $categoryName -notlike "*$Category*") { continue }

            $rows = $match.Groups[2].Value -split "`n" | Where-Object { $_ -match '^\|' }

            foreach ($row in $rows) {
                $cells = ($row -split '\|' | Where-Object { $_.Trim() }).Trim()
                if ($cells.Count -ge 4) {
                    $decisions += [PSCustomObject]@{
                        Category = $categoryName
                        Decision = $cells[0]
                        Status = $cells[1]
                        DateLocked = $cells[2]
                        Rationale = $cells[3]
                    }
                }
            }
        }
    }

    return $decisions
}

function Get-TentativeDecisions {
    <#
    .SYNOPSIS
        Get all tentative (not yet locked) decisions
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [string]$Project = "master"
    )

    $config = Get-ProjectConfig -Project $Project
    $filePath = Join-Path $config.NotesDir $config.DecisionsFile
    if (-not (Test-Path $filePath)) { return @() }

    $content = Get-Content $filePath -Raw
    $decisions = @()

    if ($content -match '## TENTATIVE DECISIONS([\s\S]*?)(?=## DEPRECATED|## DEAD|$)') {
        $rows = [regex]::Matches($Matches[1], '\| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|')

        foreach ($row in $rows) {
            if ($row.Groups[1].Value -match 'Decision') { continue }  # Skip header

            $decisions += [PSCustomObject]@{
                Decision = $row.Groups[1].Value.Trim()
                Status = $row.Groups[2].Value.Trim()
                Date = $row.Groups[3].Value.Trim()
                Notes = $row.Groups[4].Value.Trim()
            }
        }
    }

    return $decisions
}

function Get-DeadFeatures {
    <#
    .SYNOPSIS
        Get features that were explicitly cut from scope
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [string]$Project = "master"
    )

    $config = Get-ProjectConfig -Project $Project
    $filePath = Join-Path $config.NotesDir $config.DecisionsFile
    if (-not (Test-Path $filePath)) { return @() }

    $content = Get-Content $filePath -Raw
    $dead = @()

    if ($content -match '## DEAD FEATURES[^\n]*\n([\s\S]*?)(?=## Change|$)') {
        $items = [regex]::Matches($Matches[1], '- ([^\n]+)')
        foreach ($item in $items) {
            $dead += $item.Groups[1].Value.Trim()
        }
    }

    return $dead
}

# ============================================================================
# CONFLICT DETECTION
# ============================================================================

function Test-DecisionConflict {
    <#
    .SYNOPSIS
        Check if a proposal conflicts with existing locked decisions or dead features
    .PARAMETER Proposal
        The proposed decision or feature to check
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    .EXAMPLE
        Test-DecisionConflict -Proposal "Use Firebase for backend" -Project rufus
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Proposal,
        [string]$Project = "master"
    )

    $conflicts = @()
    $proposalLower = $Proposal.ToLower()
    $proposalWords = $proposalLower -split '\s+' | Where-Object { $_.Length -gt 3 }

    # Check against locked decisions
    $locked = Get-LockedDecisions -Project $Project
    foreach ($d in $locked) {
        $decisionLower = $d.Decision.ToLower()
        $decisionWords = $decisionLower -split '\s+' | Where-Object { $_.Length -gt 3 }

        # Find overlapping significant words
        $overlap = $proposalWords | Where-Object { $decisionWords -contains $_ }

        if ($overlap.Count -ge 2) {
            $conflicts += [PSCustomObject]@{
                Type = "LOCKED_CONFLICT"
                Severity = "High"
                ExistingDecision = $d.Decision
                Category = $d.Category
                Rationale = $d.Rationale
                MatchingTerms = ($overlap -join ", ")
            }
        }
    }

    # Check against dead features
    $dead = Get-DeadFeatures -Project $Project
    foreach ($feature in $dead) {
        $featureLower = $feature.ToLower()

        # Check if proposal mentions dead feature
        if ($proposalLower -match [regex]::Escape($featureLower.Substring(0, [Math]::Min(15, $featureLower.Length)))) {
            $conflicts += [PSCustomObject]@{
                Type = "DEAD_FEATURE"
                Severity = "Critical"
                Feature = $feature
                Warning = "This feature was explicitly cut from scope"
            }
        }
    }

    return [PSCustomObject]@{
        Proposal = $Proposal
        HasConflicts = ($conflicts.Count -gt 0)
        ConflictCount = $conflicts.Count
        Conflicts = $conflicts
    }
}

# ============================================================================
# SESSION HISTORY
# ============================================================================

function Get-SessionIndex {
    <#
    .SYNOPSIS
        Load the session index JSON
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [string]$Project = "master"
    )

    $config = Get-ProjectConfig -Project $Project
    $filePath = Join-Path $config.NotesDir $config.SessionIndex
    if (-not (Test-Path $filePath)) {
        return @{ sessions = @(); tags = @{}; decisions = @() }
    }

    return Get-Content $filePath -Raw | ConvertFrom-Json
}

function Search-BrainstormSessions {
    <#
    .SYNOPSIS
        Search past brainstorm sessions by topic or tag
    .PARAMETER Query
        Search term to match against topic, summary, or tags
    .PARAMETER Limit
        Maximum results to return (default 10)
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [int]$Limit = 10,
        [string]$Project = "master"
    )

    $index = Get-SessionIndex -Project $Project
    $queryLower = $Query.ToLower()

    $matches = $index.sessions | Where-Object {
        $_.topic.ToLower() -like "*$queryLower*" -or
        $_.summary.ToLower() -like "*$queryLower*" -or
        ($_.tags -and ($_.tags -join " ").ToLower() -like "*$queryLower*")
    }

    return $matches | Select-Object -First $Limit
}

function Get-SessionsByTag {
    <#
    .SYNOPSIS
        Get all sessions with a specific tag
    .PARAMETER Tag
        The tag to filter by
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Tag,
        [string]$Project = "master"
    )

    $index = Get-SessionIndex -Project $Project
    $tagLower = $Tag.ToLower()

    $sessionIds = $index.tags.$tagLower
    if (-not $sessionIds) { return @() }

    return $index.sessions | Where-Object { $sessionIds -contains $_.id }
}

# ============================================================================
# CONTEXT GATHERING FOR DEBATES
# ============================================================================

function Get-DebateContext {
    <#
    .SYNOPSIS
        Get full context for a new debate topic including decisions, past sessions, and conflicts
    .PARAMETER Topic
        The debate topic
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Topic,
        [string]$Project = "master"
    )

    # Extract keywords
    $keywords = ($Topic.ToLower() -split '\s+') | Where-Object { $_.Length -gt 4 }

    # Get relevant locked decisions
    $allLocked = Get-LockedDecisions -Project $Project
    $relevantLocked = $allLocked | Where-Object {
        $d = $_
        $keywords | Where-Object { $d.Decision.ToLower() -like "*$_*" -or $d.Category.ToLower() -like "*$_*" }
    }

    # Get tentative decisions
    $tentative = Get-TentativeDecisions -Project $Project

    # Get dead features
    $dead = Get-DeadFeatures -Project $Project

    # Search related sessions
    $relatedSessions = Search-BrainstormSessions -Query $Topic -Limit 5 -Project $Project

    # Check for conflicts
    $conflicts = Test-DecisionConflict -Proposal $Topic -Project $Project

    return [PSCustomObject]@{
        Topic = $Topic
        RelevantLockedDecisions = $relevantLocked
        TentativeDecisions = $tentative
        DeadFeatures = $dead
        RelatedPastSessions = $relatedSessions
        PotentialConflicts = $conflicts.Conflicts
        HasConflicts = $conflicts.HasConflicts
        ContextSummary = @"
## KB Context for: $Topic

### Relevant Locked Decisions ($($relevantLocked.Count) found)
$($relevantLocked | ForEach-Object { "- [$($_.Category)] $($_.Decision)" } | Out-String)

### Tentative Decisions ($($tentative.Count) total)
$($tentative | ForEach-Object { "- $($_.Decision)" } | Out-String)

### Dead Features (DO NOT PROPOSE)
$($dead | ForEach-Object { "- $_" } | Out-String)

### Related Past Sessions ($($relatedSessions.Count) found)
$($relatedSessions | ForEach-Object { "- $($_.topic) ($($_.date))" } | Out-String)

$(if ($conflicts.HasConflicts) { "### WARNING: $($conflicts.ConflictCount) POTENTIAL CONFLICTS DETECTED" })
"@
    }
}

function Format-KBContext {
    <#
    .SYNOPSIS
        Format KB context as a prompt prefix for AI debates
    .PARAMETER Topic
        The debate topic
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "master"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Topic,
        [string]$Project = "master"
    )

    $context = Get-DebateContext -Topic $Topic -Project $Project

    return @"
[KNOWLEDGE BASE CONTEXT]
Before responding, review these existing decisions and constraints:

$($context.ContextSummary)

RULES:
1. Do NOT propose features that conflict with LOCKED decisions
2. Do NOT resurrect DEAD features
3. Reference relevant past sessions for continuity
4. If proposing changes to TENTATIVE decisions, explain why
$(if ($context.HasConflicts) { "5. ADDRESS THE CONFLICTS ABOVE EXPLICITLY" })

[END KB CONTEXT]

"@
}

# ============================================================================
# SPRINT & ROADMAP
# ============================================================================

function Get-SprintStatus {
    <#
    .SYNOPSIS
        Get current 90-day sprint status
    .PARAMETER Week
        Optional: Get status for specific week (1-13)
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "rufus"
    #>
    param(
        [int]$Week,
        [string]$Project = "rufus"
    )

    $config = Get-ProjectConfig -Project $Project
    $sprintFile = if ($config.SprintFile) { $config.SprintFile } else { $script:KBConfig.SprintFile }
    $filePath = Join-Path $config.NotesDir $sprintFile
    if (-not (Test-Path $filePath)) {
        return "Sprint file not found"
    }

    $content = Get-Content $filePath -Raw

    if ($Week) {
        if ($content -match "### WEEKS? $Week[^#]*(?=### WEEK|## |$)") {
            return $Matches[0]
        }
        return "Week $Week not found"
    }

    return $content
}

function Get-Roadmap {
    <#
    .SYNOPSIS
        Get vision roadmap
    .PARAMETER Phase
        Optional: Get specific phase (1, 2, or 3)
    .PARAMETER Project
        Project name (e.g., "rufus", "master"). Default: "rufus"
    #>
    param(
        [int]$Phase,
        [string]$Project = "rufus"
    )

    $config = Get-ProjectConfig -Project $Project
    $roadmapFile = if ($config.RoadmapFile) { $config.RoadmapFile } else { $script:KBConfig.RoadmapFile }
    $filePath = Join-Path $config.NotesDir $roadmapFile
    if (-not (Test-Path $filePath)) {
        return "Roadmap file not found"
    }

    $content = Get-Content $filePath -Raw

    if ($Phase) {
        if ($content -match "## Phase $Phase[^#]*(?=## Phase|## Decision Gates|$)") {
            return $Matches[0]
        }
        return "Phase $Phase not found"
    }

    return $content
}

# ============================================================================
# EXPORTS
# ============================================================================

# Export all public functions
Export-ModuleMember -Function @(
    'Get-ProjectConfig',
    'Get-RegisteredProjects',
    'Get-LockedDecisions',
    'Get-TentativeDecisions',
    'Get-DeadFeatures',
    'Test-DecisionConflict',
    'Get-SessionIndex',
    'Search-BrainstormSessions',
    'Get-SessionsByTag',
    'Get-DebateContext',
    'Format-KBContext',
    'Get-SprintStatus',
    'Get-Roadmap'
) -ErrorAction SilentlyContinue  # Suppress if not loaded as module
