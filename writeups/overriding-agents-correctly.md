# Overriding Claude Code's Built-in Agents

Claude Code has several built-in agents you are unable to directly modify. If you are a power user this is undesirable, especially as some of those agents run on Haiku which has considerably weaker reasoning than Opus. This post covers what I know about bypassing these agents and replacing them with your own, without breaking how Claude Code functions normally.

## The Built-in Agents

Named exactly as they are named internally, the odd naming schema is Anthropic's oversight/intention, not mine. Each entry includes information on how the agent is defined in Claude Code's source code, especially useful for grabbing the system prompt and modifying it for your own agent.

All agent definitions, system prompts, and scripts referenced here are available at:
https://github.com/AnExiledDev/Claude-Code-Research/tree/main/built-in-agents/v2.1.27
(There may be a newer version available, these are for Claude Code v2.1.27.)

| Agent | Model | Purpose |
|-------|-------|---------|
| **Explore** | Haiku | Explores the codebase. Fast but shallow reasoning. |
| **Plan** | Inherited | Writes implementation plans using your session model. |
| **general-purpose** | Inherited | Fallback agent when no specialized agent fits. |
| **Bash** | Inherited | Executes bash commands. Has a minimal system prompt. |
| **statusline-setup** | Sonnet | Configures Claude Code's status line for the user. |
| **claude-code-guide** | Haiku | Searches Claude Code's documentation to answer questions about Claude Code. |

"Inherited" means the agent uses whatever model you've selected for the current session.

The two that hurt most are **Explore** and **claude-code-guide**, both locked to Haiku. If you're running Opus and expect Opus-level reasoning from your subagents, you're not getting it from these two out of the box.

## How Agent Spawning Works

When Claude Code needs a subagent, it calls the **Task** tool internally. The Task tool accepts parameters like `subagent_type`, `prompt`, `model`, and `description`. This is the interception point.

The **PreToolUse** hook fires immediately before any tool executes, including the Task tool. By intercepting the Task call, you can rewrite its parameters before Claude Code acts on them. Swap the agent type, override the model, augment the prompt, or all three.

Docs: https://code.claude.com/docs/en/hooks#pretooluse

## Redirecting an Agent

Two pieces are needed: the hook configuration and a script that does the actual redirection.

### The Hook Configuration

Add this to `~/.claude/settings.json` (global) or `.claude/settings.json` (project scope):

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

The `matcher` targets the Task tool specifically. Every time Claude Code is about to spawn a subagent, your script gets a chance to intercept it.

### The Script (`redirect-explore.sh`)

This is the minimal version. It checks if the agent being spawned is `Explore`, and if so, swaps it to a custom agent named `research`. This assumes you have an agent defined at `.claude/agents/research.md`.

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

The key mechanism is `updatedInput`. Any fields you return here replace the matching fields in the original tool input before execution. Return only what you want to change, everything else passes through untouched.

If the agent isn't `Explore`, the script exits with code 0 and no stdout, which tells Claude Code to proceed normally without modification.

## Going Further

This is where the true power of hooks shine, it's incredible what is possible now. This does what the above script does and then some:

- Prepends instructions to the prompt that is being sent by Claude Code for the tool call. (`PROMPT_PREFIX`)
- Forces a specific model, and although I have not confirmed, it should also be possible to change the Explore agent's model this way, WITHOUT replacing the agent. (`MODEL_OVERRIDE`)
- Optionally redirects to a different agent if the prompt matches certain keywords. Security question? Send it to a `security-reviewer` agent instead. (`Conditional routing` section)
- Passes additional context to the agent, letting it know it was redirected, this has many different potential use-cases. (`additionalContext`)
- Defines a specific debug log path for testing/debugging. (`LOG_FILE`)

### Advanced Script (`redirect-explore-advanced.sh`)

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

## What You Can Override

For reference, the full set of fields available in `updatedInput` when intercepting the Task tool:

| Field | Type | What it does |
|-------|------|-------------|
| `subagent_type` | string | Which agent handles the task |
| `prompt` | string | The instructions sent to the agent |
| `model` | string | Model to use (`sonnet`, `opus`, `haiku`) |
| `description` | string | Short description shown in the UI |
| `max_turns` | number | Maximum API round-trips before the agent stops |

You only need to include the fields you want to change. Everything else passes through from the original call.

## Notes

- Your custom agent must exist either as a built-in name or as a `.md` file in `.claude/agents/`.
- The `permissionDecision: "allow"` in the hook response bypasses the permission prompt. Use `"ask"` if you want the user to confirm each redirect, or `"deny"` to block specific agent spawns entirely.
- Run `claude --debug` to verify your hook is firing. You'll see hook execution in the debug output.
- The `timeout` in the hook config (in seconds) prevents a broken script from hanging Claude Code indefinitely. 10 seconds is generous for these scripts.
