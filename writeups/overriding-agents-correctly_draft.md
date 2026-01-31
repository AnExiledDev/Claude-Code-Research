Claude Code has several built-in agents you are unable to directly modify. If you are a power user this is undesirable, especially as some of the built-in agents utilize Haiku which has considerably weaker reasoning than Opus. This post explores methods I know of that allow you to bypass these agents, and use your own without interfering with how Claude Code functions normally.

### The Built-in Agents
Named exactly as they are named internally, the odd naming schema is Anthropic's oversight/intention, not mine. Each includes information on how the agent is defined in Claude Code's source code, especially useful for grabbing the system prompt and modifying it for your own agent.

You can see all information, including the agents system prompt here and all scripts shared: https://github.com/AnExiledDev/Claude-Code-Research/tree/main/built-in-agents/v2.1.27 (There may be newer version available, these are for claude code version 2.1.27.

**Explore** - Explores the codebase using the Haiku agent.
**Plan** - Writes plans using the same model as you have chosen for the session.
**general-purpose** - Default agent used when a better agent does not exist, uses the same model as you have chosen for the session.
**Bash** - Executes Bash commands, has a simple system prompt, uses the same model as you have chosen for the session.
**statusline-setup** - Helps configure Claude Code's statusline for the user, uses the Sonnet model.
**claude-code-guide** - Searches Claude Code's documentation to answer users questions abotu Claude Code, uses the Haiku agent.
### Redirecting Internal Agent Calls to your Agent
Claude Code spawns agents by calling the "Task" tool, which empowers instructing Claude Code to utilize your custom agent. You do this through utilizing the PreToolUse hook which fires immediately before a tool, like the Task tool, is called. (Docs: https://code.claude.com/docs/en/hooks#pretooluse)

**The Hook**
Add to `~/.claude/settings.json` or in your project scope at `.claude/settings.json`
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/redirect-explore.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**The Script (`redirect-explore.sh`)**
This assumes you have an agent named `research.md` in `/.claude/agents` folder.
```bash
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
```
**Bonus Functionality**
This is where the true power of hooks shine, it's incredible what is possible now. This does what the above script does and then some:

- Prepends instructions to the prompt that is being sent by Claude Code for the tool call. (`PROMPT_PREFIX`)
- Forces a specific model, and although I have not confirmed, it should also be possible to change the Explore agents model this way, WITHOUT replacing the agent. (`MODEL_OVERRIDE`)
- Optionally redirects to a different security-reviewer agent if the question relates to security. (`Conditional routing` section)
- Passed additional context to the agent, letting it know it was redirected, this has many different potential use-cases. (`additionalContext`)
- Defines a specific debug log path for testing/debugging. (`LOG_FILE`)

```bash
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
```
