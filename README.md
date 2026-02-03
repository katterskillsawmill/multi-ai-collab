# Multi-AI Collaboration System

This system enables Claude, Codex/GPT-4, Gemini, and Grok to work together on code reviews through GitHub.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub (Central Hub)                         │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐     │
│  │   PR     │   │  Issues  │   │ Comments │   │ Actions  │     │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘     │
│       │              │              │              │            │
│       └──────────────┴──────────────┴──────────────┘            │
│                              │                                   │
│                    ┌─────────▼─────────┐                        │
│                    │  AI Note Router   │                        │
│                    │  @ai:<model>      │                        │
│                    └─────────┬─────────┘                        │
│       ┌──────────────────────┼──────────────────────┐          │
│       │              │              │               │          │
│  ┌────▼────┐   ┌────▼────┐   ┌────▼────┐   ┌──────▼────┐     │
│  │ Claude  │   │ Gemini  │   │ Codex   │   │   Grok    │     │
│  │(Arch)   │   │(Security)│   │(Quality)│   │(Creative) │     │
│  └────┬────┘   └────┬────┘   └────┬────┘   └─────┬─────┘     │
│       │              │              │              │            │
│       └──────────────┴──────────────┴──────────────┘            │
│                              │                                   │
│                    ┌─────────▼─────────┐                        │
│                    │  Response Posted  │                        │
│                    │  + Tag Next AI    │                        │
│                    └───────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

## Setup

### 1. GitHub Secrets Required

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret | Description | Get it from |
|--------|-------------|-------------|
| `ANTHROPIC_API_KEY` | Claude API key | https://console.anthropic.com |
| `OPENAI_API_KEY` | GPT-4/Codex key | https://platform.openai.com |
| `GOOGLE_API_KEY` | Gemini API key | https://aistudio.google.com |
| `XAI_API_KEY` | Grok API key | https://x.ai |

### 2. Enable Workflows

The workflows are in `.github/workflows/`:
- `multi-ai-review.yml` - Automatic parallel review on PRs
- `ai-collaboration.yml` - AI note-passing system

## Usage

### Automatic PR Review

Every PR automatically gets reviewed by all 4 AIs in parallel. Each focuses on their specialty:

- **Claude**: Architecture, design patterns, scalability
- **Codex/GPT-4**: Code quality, best practices, testing
- **Gemini**: Security vulnerabilities, documentation
- **Grok**: Edge cases, creative insights

### AI Notes System

AIs can leave notes for each other using tags:

```markdown
@ai:claude Please review the architectural implications of this change

@ai:gemini Check if this introduces any security vulnerabilities

@ai:codex Suggest better patterns for this code

@ai:grok What edge cases might we be missing?

@ai:all Everyone please weigh in on this
```

### Example Conversation

```markdown
# Issue: Review authentication refactor

**Human**: @ai:claude Please review this auth service refactor

---

### 🧠 Claude's Response
The refactor looks good architecturally. The separation of concerns is improved.
However, I'm concerned about the token refresh logic.
@ai:gemini Can you check the security implications of the new token storage?

---

### 🔒 Gemini's Response
Good catch, Claude. The token is being stored in localStorage which is vulnerable
to XSS attacks. Recommendation: Use httpOnly cookies instead.
@ai:codex What's the best practice pattern for this in Flutter?

---

### 💻 Codex's Response
For Flutter, use flutter_secure_storage package. Here's a pattern...
@ai:grok Any edge cases we should consider?

---

### 🚀 Grok's Response
What if the device clock is wrong? Token expiry checks could fail...
```

## Local CLI Usage

For local development, use the PowerShell script:

```powershell
# Review a file
.\scripts\multi-ai-review.ps1 -Path "lib/services/auth_service.dart"

# Review a PR
.\scripts\multi-ai-review.ps1 -PR 123

# Output as markdown
.\scripts\multi-ai-review.ps1 -Path "lib/" -Output markdown > review.md
```

## MCP Server (Claude Code Integration)

Add the MCP server to your Claude Code config to call other AIs directly:

**~/.claude/claude_desktop_config.json**:
```json
{
  "mcpServers": {
    "ai-orchestrator": {
      "command": "node",
      "args": ["path/to/scripts/mcp-servers/ai-orchestrator-server.js"],
      "env": {
        "GOOGLE_API_KEY": "your-key",
        "OPENAI_API_KEY": "your-key",
        "XAI_API_KEY": "your-key"
      }
    }
  }
}
```

Then in Claude Code:
```
> Ask Gemini to review this code for security issues
> Get a multi-AI review of this function
```

## Gemini CLI Custom Agent

Use the custom Gemini agent for focused reviews:

```bash
# Install Gemini CLI
npm install -g @anthropic-ai/gemini-cli

# Use custom agent
gemini --agent scripts/ai-agents/gemini-code-reviewer.json
```

## Best Practices

1. **Be specific** when tagging AIs - tell them what to focus on
2. **Chain reviews** - let AIs build on each other's insights
3. **Use @ai:all** sparingly - it can generate a lot of output
4. **Human final say** - AIs provide input, humans decide

## Cost Considerations

Each AI call costs tokens. To minimize costs:
- Use specific tags instead of @ai:all
- Truncate large diffs (done automatically)
- Use cheaper models for initial passes

## Troubleshooting

**AI not responding?**
- Check API key is set correctly
- Check workflow run logs in Actions tab
- Ensure the comment contains a valid tag

**Rate limited?**
- Add delays between AI calls
- Use smaller code snippets
- Upgrade API tier

## Files

```
scripts/
├── multi-ai-review.ps1          # Local CLI orchestrator
├── ai-agents/
│   └── gemini-code-reviewer.json # Custom Gemini agent
├── mcp-servers/
│   └── ai-orchestrator-server.js # MCP server for Claude Code
└── AI_COLLABORATION_README.md    # This file

.github/workflows/
├── multi-ai-review.yml           # Auto PR review
└── ai-collaboration.yml          # AI notes system
```
