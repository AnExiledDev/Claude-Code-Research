#!/bin/bash
# redirect-explore-advanced.sh
# Advanced Explore agent interception with prompt augmentation,
# model override, and conditional routing.
#
# Install:
#   1. Copy to .claude/hooks/ and chmod +x
#   2. Add PreToolUse config from settings-example.json to your .claude/settings.json
#      (change the command path to point to this script)
#   3. Run `claude --debug` to verify

INPUT=$(cat)

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [ "$SUBAGENT_TYPE" != "Explore" ]; then
  exit 0
fi

ORIGINAL_PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
ORIGINAL_MODEL=$(echo "$INPUT" | jq -r '.tool_input.model // empty')

# --- Configuration ---
TARGET_AGENT="research"          # must exist as built-in or in .claude/agents/
MODEL_OVERRIDE="opus"            # force a specific model (sonnet, opus, haiku)
PROMPT_PREFIX="Follow project conventions in CLAUDE.md. Cite file paths for all findings."
LOG_FILE="/tmp/explore-hook.log"  # set to "" to disable logging

# --- Conditional routing ---
# Route security-related prompts to a dedicated agent if it exists
if echo "$ORIGINAL_PROMPT" | grep -qiE '(security|auth|credential|secret|vulnerabilit)'; then
  TARGET_AGENT="security-reviewer"
  PROMPT_PREFIX="Focus on security implications. Flag any exposed secrets or unsafe patterns."
fi

# --- Logging (optional) ---
if [ -n "$LOG_FILE" ]; then
  echo "[$(date -Iseconds)] Redirecting Explore → ${TARGET_AGENT} (model: ${MODEL_OVERRIDE})" >> "$LOG_FILE"
  echo "  Original prompt: ${ORIGINAL_PROMPT:0:200}" >> "$LOG_FILE"
fi

# --- Build augmented prompt safely ---
AUGMENTED_PROMPT=$(jq -n \
  --arg prefix "$PROMPT_PREFIX" \
  --arg orig "$ORIGINAL_PROMPT" \
  '$prefix + "\n\n" + $orig')

# --- Emit hook response ---
jq -n \
  --arg agent_type "$TARGET_AGENT" \
  --argjson prompt "$AUGMENTED_PROMPT" \
  --arg model "$MODEL_OVERRIDE" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: ("Redirected Explore to " + $agent_type),
      updatedInput: {
        subagent_type: $agent_type,
        prompt: $prompt,
        model: $model
      },
      additionalContext: "This task was routed by the redirect-explore-advanced hook."
    }
  }'
