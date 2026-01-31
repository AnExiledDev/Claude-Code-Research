#!/bin/bash
# redirect-explore.sh
# Redirects Explore agent spawns to a custom agent type.
#
# Install:
#   1. Copy to .claude/hooks/ and chmod +x
#   2. Add PreToolUse config from settings-example.json to your .claude/settings.json
#   3. Run `claude --debug` to verify

INPUT=$(cat)

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [ "$SUBAGENT_TYPE" != "Explore" ]; then
  exit 0
fi

# Target agent must exist as a built-in or in .claude/agents/
TARGET_AGENT="research"

jq -n --arg agent_type "$TARGET_AGENT" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: "Redirected Explore to custom agent",
      updatedInput: {
        subagent_type: $agent_type
      }
    }
  }'
