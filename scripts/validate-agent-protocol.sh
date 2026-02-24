#!/usr/bin/env bash
set -euo pipefail

# Validate cross-agent protocol files across ABKC repos
# Usage: bash validate-agent-protocol.sh [repo-name]

REPOS=(
  "$HOME/dog-show-app"
  "$HOME/ABKC-website"
  "$HOME/abkc-show-host"
  "$HOME/abkc-academy"
  "$HOME/abkc-design-system"
)

errors=0
warnings=0

check_repo() {
  local repo="$1"
  local name
  name=$(basename "$repo")

  echo "=== $name ==="

  # Check directory structure
  for dir in ".codex/tasks" ".claude/replies"; do
    if [ ! -d "$repo/$dir" ]; then
      echo "  ERROR: Missing directory: $dir"
      ((errors++))
    fi
  done

  # Check required files
  for file in ".codex/config.toml" "AGENTS.md"; do
    if [ ! -f "$repo/$file" ]; then
      echo "  ERROR: Missing file: $file"
      ((errors++))
    fi
  done

  # Check Claude skill
  if [ ! -f "$repo/.claude/skills/cross-agent-handoff/SKILL.md" ]; then
    echo "  WARNING: Missing cross-agent-handoff skill"
    ((warnings++))
  fi

  # Check GitHub templates
  for tmpl in ".github/ISSUE_TEMPLATE/agent-task.md" ".github/PULL_REQUEST_TEMPLATE/codex-pr.md"; do
    if [ ! -f "$repo/$tmpl" ]; then
      echo "  WARNING: Missing template: $tmpl"
      ((warnings++))
    fi
  done

  # Validate task files
  local pending=0 in_progress=0 completed=0 orphaned=0
  if [ -d "$repo/.codex/tasks" ]; then
    for task in "$repo/.codex/tasks/"*.md; do
      [ -f "$task" ] || continue
      local basename_task
      basename_task=$(basename "$task")

      # Check YAML frontmatter exists
      if ! head -1 "$task" | grep -q "^---"; then
        echo "  ERROR: Task $basename_task missing YAML frontmatter"
        ((errors++))
        continue
      fi

      # Check required fields
      for field in "id:" "author:" "assignee:" "status:"; do
        if ! head -15 "$task" | grep -q "$field"; then
          echo "  ERROR: Task $basename_task missing field: $field"
          ((errors++))
        fi
      done

      # Count by status
      local status
      status=$(head -15 "$task" | grep "status:" | sed 's/status:\s*//' | tr -d ' "')
      case "$status" in
        pending) ((pending++)) ;;
        in_progress) ((in_progress++)) ;;
        completed) ((completed++)) ;;
        *) echo "  WARNING: Task $basename_task has unknown status: $status"; ((warnings++)) ;;
      esac

      # Check for orphaned tasks (pending > 7 days)
      local created
      created=$(head -15 "$task" | grep "created:" | sed 's/created:\s*//' | tr -d '"')
      if [ -n "$created" ]; then
        local created_epoch now_epoch age_days
        created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        if [ "$created_epoch" -gt 0 ]; then
          age_days=$(( (now_epoch - created_epoch) / 86400 ))
          if [ "$age_days" -gt 7 ] && [ "$status" = "pending" ]; then
            echo "  WARNING: Task $basename_task pending for $age_days days"
            ((warnings++))
            ((orphaned++))
          fi
        fi
      fi
    done
  fi

  # Validate reply files
  local replies=0 orphaned_replies=0
  if [ -d "$repo/.claude/replies" ]; then
    for reply in "$repo/.claude/replies/"*-reply.md; do
      [ -f "$reply" ] || continue
      ((replies++))
      local basename_reply
      basename_reply=$(basename "$reply")

      # Check task_id reference
      local task_id
      task_id=$(head -10 "$reply" | grep "task_id:" | sed 's/task_id:\s*//' | tr -d ' "')
      if [ -z "$task_id" ]; then
        echo "  ERROR: Reply $basename_reply missing task_id"
        ((errors++))
      fi
    done
  fi

  echo "  Tasks:   $pending pending | $in_progress in-progress | $completed completed"
  echo "  Replies: $replies"
  if [ "$orphaned" -gt 0 ]; then
    echo "  Orphaned: $orphaned tasks pending > 7 days"
  fi
  echo ""
}

# Run validation
if [ "${1:-}" ]; then
  # Single repo
  for repo in "${REPOS[@]}"; do
    if [ "$(basename "$repo")" = "$1" ]; then
      check_repo "$repo"
      break
    fi
  done
else
  # All repos
  for repo in "${REPOS[@]}"; do
    if [ -d "$repo" ]; then
      check_repo "$repo"
    fi
  done
fi

echo "=== Summary ==="
echo "  Errors:   $errors"
echo "  Warnings: $warnings"

if [ "$errors" -gt 0 ]; then
  exit 1
fi
