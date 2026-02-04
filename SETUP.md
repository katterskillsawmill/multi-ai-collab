# Multi-AI Collaboration Setup Guide

## Quick Start

### 1. Get Your API Keys

| Service | Get Key From | Model Used |
|---------|--------------|------------|
| **Claude** | [console.anthropic.com](https://console.anthropic.com) | claude-sonnet-4-20250514 |
| **GPT-4** | [platform.openai.com](https://platform.openai.com) | gpt-4o |
| **Gemini** | [aistudio.google.com](https://aistudio.google.com) | gemini-1.5-pro |
| **Grok** | [x.ai](https://x.ai) | grok-2-latest |

### 2. Add Secrets to GitHub

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** for each:

| Secret Name | Value |
|-------------|-------|
| `ANTHROPIC_API_KEY` | Your Claude API key (starts with `sk-ant-`) |
| `OPENAI_API_KEY` | Your OpenAI API key (starts with `sk-`) |
| `GOOGLE_API_KEY` | Your Google AI Studio key |
| `XAI_API_KEY` | Your X.AI/Grok API key |

### 3. Enable Workflows

The workflows should be enabled by default. If not:

1. Go to **Actions** tab in your repository
2. Click **I understand my workflows, go ahead and enable them**

## How It Works

### Automatic PR Reviews

When you open or update a PR, all 4 AIs review it in parallel:

```
PR Opened → 4 AIs review simultaneously → Consolidated comment posted
```

Each AI has a specialty:
- **Claude** 🧠 - Architecture, scalability, system design
- **GPT-4** 💻 - Code quality, best practices, testing
- **Gemini** 🔒 - Security vulnerabilities, documentation
- **Grok** 🚀 - Edge cases, creative insights

### AI Notes System

Tag an AI in any issue or PR comment to get their input:

```markdown
@ai:claude What are the architectural implications of this change?

@ai:gpt4 Can you suggest a cleaner pattern for this code?

@ai:gemini Are there any security concerns here?

@ai:grok What edge cases might we be missing?

@ai:all Everyone please review this approach
```

AIs can also tag each other to continue the conversation!

## Cost Estimates

| Event | API Calls | Est. Cost |
|-------|-----------|-----------|
| PR Review | 4 calls | ~$0.10-0.30 |
| Single AI Note | 1 call | ~$0.02-0.05 |
| @ai:all Note | 4 calls | ~$0.10-0.30 |

*Costs vary based on diff size and response length*

## Troubleshooting

### "API key not configured"
- Check that the secret name matches exactly (case-sensitive)
- Verify the key is valid and has credits

### "API error: 401"
- API key is invalid or expired
- Regenerate the key and update the secret

### "API error: 429"
- Rate limit exceeded
- Wait a few minutes or upgrade your API tier

### AI not responding to tags
- Make sure the tag format is correct: `@ai:claude` (not `@claude` or `@ai-claude`)
- Check the Actions tab for workflow run logs

### Empty or partial reviews
- Large diffs are truncated to ~80KB
- If all AIs fail, check your API keys

## Customization

### Change AI Models

Edit the workflow files in `.github/workflows/`:

```yaml
# In multi-ai-review.yml or ai-collaboration.yml
model: 'claude-sonnet-4-20250514'  # Change to different Claude model
model: 'gpt-4o'                     # Change to gpt-4-turbo, etc.
model: 'gemini-1.5-pro'             # Change to gemini-1.5-flash for speed
model: 'grok-2-latest'              # Change to other Grok models
```

### Adjust Token Limits

```yaml
max_tokens: 2000  # Increase for longer reviews, decrease to save costs
```

### Customize AI Personalities

Edit the system prompts in the workflow files to change how each AI responds.

## Files

```
.github/workflows/
├── multi-ai-review.yml      # Automatic PR review (4 AIs in parallel)
└── ai-collaboration.yml     # AI notes system (@ai:model tags)
```

## Support

If you encounter issues:
1. Check the **Actions** tab for detailed error logs
2. Verify all secrets are set correctly
3. Test each API key individually with curl
