#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool tool_name] [--cmd command] [--input-method stdin|file|arg|env|none] [--prompt-file file_path] [--config config_path] [max_iterations]

set -e

# Verify jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: 'jq' command-line JSON processor is required but not installed."
  echo "Please install it (e.g. 'brew install jq' on macOS) and try again."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
CONFIG_FILE="$SCRIPT_DIR/ralph.config.json"
STATUS_FILE="$SCRIPT_DIR/status.json"

# Default configuration settings
DEFAULT_TOOL="amp"
DEFAULT_MAX_ITERATIONS=10

# Load defaults from configuration file if it exists
if [ -f "$CONFIG_FILE" ]; then
  CFG_DEFAULT_TOOL=$(jq -r '.defaultTool // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  if [ -n "$CFG_DEFAULT_TOOL" ]; then
    DEFAULT_TOOL="$CFG_DEFAULT_TOOL"
  fi
  CFG_MAX_ITERATIONS=$(jq -r '.maxIterations // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  if [ -n "$CFG_MAX_ITERATIONS" ] && [[ "$CFG_MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    DEFAULT_MAX_ITERATIONS="$CFG_MAX_ITERATIONS"
  fi
fi

# Variables for command line parsing
TOOL="$DEFAULT_TOOL"
MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"
CMD_OVERRIDE=""
INPUT_METHOD_OVERRIDE=""
PROMPT_FILE_OVERRIDE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --cmd|--command)
      CMD_OVERRIDE="$2"
      shift 2
      ;;
    --cmd=*|--command=*)
      CMD_OVERRIDE="${1#*=}"
      shift
      ;;
    --input-method)
      INPUT_METHOD_OVERRIDE="$2"
      shift 2
      ;;
    --input-method=*)
      INPUT_METHOD_OVERRIDE="${1#*=}"
      shift
      ;;
    --prompt-file)
      PROMPT_FILE_OVERRIDE="$2"
      shift 2
      ;;
    --prompt-file=*)
      PROMPT_FILE_OVERRIDE="${1#*=}"
      shift
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --config=*)
      CONFIG_FILE="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Initialize account configuration lists
declare -a ACCT_NAMES
declare -a ACCT_TOOLS
declare -a ACCT_KEYS
declare -a ACCT_VALUES
declare -a ACCT_LIMIT_HIT

# Check if CONFIG_FILE has an 'accounts' array
HAS_JSON_ACCOUNTS=false
if [ -f "$CONFIG_FILE" ]; then
  JSON_ACCOUNTS_COUNT=$(jq '.accounts // empty | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
  if [ "$JSON_ACCOUNTS_COUNT" -gt 0 ]; then
    HAS_JSON_ACCOUNTS=true
  fi
fi

if [ "$HAS_JSON_ACCOUNTS" = "true" ]; then
  echo "Loading accounts list from configuration file: $CONFIG_FILE"
  for idx in $(seq 0 $((JSON_ACCOUNTS_COUNT - 1))); do
    NAME=$(jq -r ".accounts[$idx].name" "$CONFIG_FILE")
    TOOL_NAME=$(jq -r ".accounts[$idx].tool" "$CONFIG_FILE")
    
    ACCT_NAMES+=("$NAME")
    ACCT_TOOLS+=("$TOOL_NAME")
    ACCT_LIMIT_HIT+=("false")
    
    # Store first env variable name and value for backward compatibility / fallback
    API_KEY_VAR=$(jq -r ".accounts[$idx].env | keys[] // empty" "$CONFIG_FILE" | head -n 1)
    if [ -n "$API_KEY_VAR" ]; then
      API_KEY_VAL=$(jq -r ".accounts[$idx].env.\"$API_KEY_VAR\"" "$CONFIG_FILE")
      ACCT_KEYS+=("$API_KEY_VAR")
      ACCT_VALUES+=("$API_KEY_VAL")
    else
      ACCT_KEYS+=("")
      ACCT_VALUES+=("")
    fi
  done
elif [ -n "$AGENT_ACCOUNTS" ]; then
  echo "Loading accounts list from AGENT_ACCOUNTS environment variable: $AGENT_ACCOUNTS"
  IFS=',' read -ra ADDR <<< "$AGENT_ACCOUNTS"
  for part in "${ADDR[@]}"; do
    part=$(echo "$part" | xargs) # trim spaces
    if [ -z "$part" ]; then continue; fi
    
    ACCT_NAMES+=("$part")
    ACCT_LIMIT_HIT+=("false")
    
    if [[ "$part" =~ claude ]]; then
      ACCT_TOOLS+=("claude")
      SUFFIX=$(echo "$part" | sed -E 's/[^0-9]//g')
      if [ -n "$SUFFIX" ]; then
        VAL_VAR="ANTHROPIC_API_KEY_$SUFFIX"
        if [ -z "${!VAL_VAR}" ] && [ -n "$ANTHROPIC_API_KEY" ]; then
          VAL_VAR="ANTHROPIC_API_KEY"
        fi
      else
        VAL_VAR="ANTHROPIC_API_KEY"
      fi
      ACCT_KEYS+=("ANTHROPIC_API_KEY")
      ACCT_VALUES+=("${!VAL_VAR}")
    elif [[ "$part" =~ (antigravity|agy) ]]; then
      ACCT_TOOLS+=("antigravity")
      SUFFIX=$(echo "$part" | sed -E 's/[^0-9]//g')
      if [ -n "$SUFFIX" ]; then
        VAL_VAR="GOOGLE_API_KEY_$SUFFIX"
        if [ -z "${!VAL_VAR}" ]; then
          VAL_VAR="ANTIGRAVITY_API_KEY_$SUFFIX"
        fi
        if [ -z "${!VAL_VAR}" ]; then
          if [ -n "$GOOGLE_API_KEY" ]; then
            VAL_VAR="GOOGLE_API_KEY"
          elif [ -n "$ANTIGRAVITY_API_KEY" ]; then
            VAL_VAR="ANTIGRAVITY_API_KEY"
          fi
        fi
      else
        if [ -n "$GOOGLE_API_KEY" ]; then
          VAL_VAR="GOOGLE_API_KEY"
        else
          VAL_VAR="ANTIGRAVITY_API_KEY"
        fi
      fi
      ACCT_KEYS+=("GOOGLE_API_KEY")
      ACCT_VALUES+=("${!VAL_VAR}")
    elif [[ "$part" =~ amp ]]; then
      ACCT_TOOLS+=("amp")
      ACCT_KEYS+=("")
      ACCT_VALUES+=("")
    else
      ACCT_TOOLS+=("$part")
      ACCT_KEYS+=("")
      ACCT_VALUES+=("")
    fi
  done
else
  # Default to a single account parsed from CLI arguments
  ACCT_NAMES+=("default")
  ACCT_TOOLS+=("$TOOL")
  ACCT_LIMIT_HIT+=("false")
  
  if [ "$TOOL" = "claude" ]; then
    ACCT_KEYS+=("ANTHROPIC_API_KEY")
    ACCT_VALUES+=("$ANTHROPIC_API_KEY")
  elif [ "$TOOL" = "antigravity" ]; then
    ACCT_KEYS+=("GOOGLE_API_KEY")
    if [ -n "$GOOGLE_API_KEY" ]; then
      ACCT_VALUES+=("$GOOGLE_API_KEY")
    else
      ACCT_VALUES+=("$ANTIGRAVITY_API_KEY")
    fi
  else
    ACCT_KEYS+=("")
    ACCT_VALUES+=("")
  fi
fi

NUM_ACCOUNTS=${#ACCT_NAMES[@]}
CURRENT_ACCT_INDEX=0

echo "Configured Accounts ($NUM_ACCOUNTS):"
for i in "${!ACCT_NAMES[@]}"; do
  echo "  [$i] Name: ${ACCT_NAMES[$i]} | Tool: ${ACCT_TOOLS[$i]} | Key: ${ACCT_KEYS[$i]:-none}"
done
echo "==============================================================="

# Track live iteration index globally
ITER_IDX=0

# Dashboard update helper
update_status_json() {
  local loop_status="$1"
  local last_msg="$2"
  
  # Build accounts array in JSON format
  local accts_json="[]"
  for idx in "${!ACCT_NAMES[@]}"; do
    local acct_name="${ACCT_NAMES[$idx]}"
    local acct_tool="${ACCT_TOOLS[$idx]}"
    local acct_status="idle"
    if [ "$loop_status" = "running" ] && [ "$idx" -eq "$CURRENT_ACCT_INDEX" ]; then
      acct_status="active"
    elif [ "${ACCT_LIMIT_HIT[$idx]:-false}" = "true" ]; then
      acct_status="rate-limited"
    fi
    
    accts_json=$(echo "$accts_json" | jq --arg name "$acct_name" --arg tool "$acct_tool" --arg status "$acct_status" '. + [{name: $name, tool: $tool, status: $status}]')
  done
  
  # Write atomically using temporary file
  jq -n \
    --arg status "$loop_status" \
    --arg msg "$last_msg" \
    --argjson iter "$ITER_IDX" \
    --argjson max "$MAX_ITERATIONS" \
    --argjson accts "$accts_json" \
    --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{status: $status, lastMessage: $msg, currentIteration: $iter, maxIterations: $max, accounts: $accts, updatedAt: $time}' \
    > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Check if tasks are already fully complete before running
if [ -f "$PRD_FILE" ]; then
  INCOMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE" 2>/dev/null || echo "-1")
  if [ "$INCOMPLETE_COUNT" -eq 0 ]; then
    echo "All user stories in $PRD_FILE are already completed!"
    update_status_json "completed" "All user stories in $PRD_FILE are already completed!"
    exit 0
  fi
fi

# Session Profile Symlink Swapping helper
manage_profiles() {
  local acct_name="$1"
  local acct_tool="$2"
  
  # Claude Code profiles
  if [ "$acct_tool" = "claude" ]; then
    local profile_dir="$HOME/.claude_$acct_name"
    if [ -d "$profile_dir" ]; then
      echo "Switching Claude profile path to $profile_dir..."
      rm -f "$HOME/.claude"
      ln -s "$profile_dir" "$HOME/.claude"
    fi
  fi

  # Antigravity/agy profiles
  if [ "$acct_tool" = "antigravity" ] || [ "$acct_tool" = "agy" ]; then
    local profile_dir="$HOME/.config/agy_$acct_name"
    if [ -d "$profile_dir" ]; then
      echo "Switching Antigravity profile path to $profile_dir..."
      rm -f "$HOME/.config/agy"
      ln -s "$profile_dir" "$HOME/.config/agy"
    fi
  fi

  # Amp profiles
  if [ "$acct_tool" = "amp" ]; then
    local profile_dir="$HOME/.config/amp_$acct_name"
    if [ -d "$profile_dir" ]; then
      echo "Switching Amp profile path to $profile_dir..."
      rm -f "$HOME/.config/amp"
      ln -s "$profile_dir" "$HOME/.config/amp"
    fi
  fi
}

echo "Starting Ralph - Agent Loop"
echo "  Max Iterations: $MAX_ITERATIONS"
echo "==============================================================="

# Update initial status
update_status_json "idle" "Loop initialized, waiting to start."

for i in $(seq 1 $MAX_ITERATIONS); do
  # Update global iteration counter
  ITER_IDX="$i"
  
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  CONSECUTIVE_SWITCHES=0

  while true; do
    ACTIVE_NAME="${ACCT_NAMES[$CURRENT_ACCT_INDEX]}"
    ACTIVE_TOOL="${ACCT_TOOLS[$CURRENT_ACCT_INDEX]}"
    ACTIVE_KEY_VAR="${ACCT_KEYS[$CURRENT_ACCT_INDEX]}"
    ACTIVE_KEY_VAL="${ACCT_VALUES[$CURRENT_ACCT_INDEX]}"

    echo "Using Account: '$ACTIVE_NAME' (Tool: $ACTIVE_TOOL)"
    update_status_json "running" "Running iteration $i using account '$ACTIVE_NAME' ($ACTIVE_TOOL)..."

    # Resolve tool-specific presets
    BUILTIN_AMP_CMD="amp --dangerously-allow-all"
    BUILTIN_AMP_INPUT_METHOD="stdin"
    BUILTIN_AMP_PROMPT="prompt.md"

    BUILTIN_CLAUDE_CMD="claude --dangerously-skip-permissions --print"
    BUILTIN_CLAUDE_INPUT_METHOD="stdin"
    BUILTIN_CLAUDE_PROMPT="CLAUDE.md"

    TOOL_CMD=""
    TOOL_INPUT_METHOD=""
    TOOL_PROMPT=""

    # Load tool settings from JSON if config file exists
    if [ -f "$CONFIG_FILE" ]; then
      TOOL_CMD=$(jq -r ".tools.\"$ACTIVE_TOOL\".cmd // empty" "$CONFIG_FILE" 2>/dev/null || echo "")
      TOOL_INPUT_METHOD=$(jq -r ".tools.\"$ACTIVE_TOOL\".inputMethod // empty" "$CONFIG_FILE" 2>/dev/null || echo "")
      TOOL_PROMPT=$(jq -r ".tools.\"$ACTIVE_TOOL\".promptFile // empty" "$CONFIG_FILE" 2>/dev/null || echo "")
    fi

    # Fallbacks to built-in presets
    if [ -z "$TOOL_CMD" ]; then
      if [ "$ACTIVE_TOOL" = "amp" ]; then
        TOOL_CMD="$BUILTIN_AMP_CMD"
      elif [ "$ACTIVE_TOOL" = "claude" ]; then
        TOOL_CMD="$BUILTIN_CLAUDE_CMD"
      fi
    fi

    if [ -z "$TOOL_INPUT_METHOD" ]; then
      if [ "$ACTIVE_TOOL" = "amp" ]; then
        TOOL_INPUT_METHOD="$BUILTIN_AMP_INPUT_METHOD"
      elif [ "$ACTIVE_TOOL" = "claude" ]; then
        TOOL_INPUT_METHOD="$BUILTIN_CLAUDE_INPUT_METHOD"
      else
        TOOL_INPUT_METHOD="stdin"
      fi
    fi

    if [ -z "$TOOL_PROMPT" ]; then
      if [ "$ACTIVE_TOOL" = "amp" ]; then
        TOOL_PROMPT="$BUILTIN_AMP_PROMPT"
      elif [ "$ACTIVE_TOOL" = "claude" ]; then
        TOOL_PROMPT="$BUILTIN_CLAUDE_PROMPT"
      else
        TOOL_UPPER=$(echo "$ACTIVE_TOOL" | tr '[:lower:]' '[:upper:]')
        if [ -f "$SCRIPT_DIR/$TOOL_UPPER.md" ]; then
          TOOL_PROMPT="$TOOL_UPPER.md"
        else
          TOOL_PROMPT="prompt.md"
        fi
      fi
    fi

    # Apply overrides (only if they were passed explicitly via CLI)
    if [ -n "$CMD_OVERRIDE" ]; then
      TOOL_CMD="$CMD_OVERRIDE"
    fi
    if [ -n "$INPUT_METHOD_OVERRIDE" ]; then
      TOOL_INPUT_METHOD="$INPUT_METHOD_OVERRIDE"
    fi
    if [ -n "$PROMPT_FILE_OVERRIDE" ]; then
      TOOL_PROMPT="$PROMPT_FILE_OVERRIDE"
    fi

    # Ensure command exists
    if [ -z "$TOOL_CMD" ]; then
      TOOL_CMD="$ACTIVE_TOOL"
    fi

    # Resolve prompt file path
    if [[ "$TOOL_PROMPT" = /* ]]; then
      RESOLVED_PROMPT_FILE="$TOOL_PROMPT"
    else
      RESOLVED_PROMPT_FILE="$SCRIPT_DIR/$TOOL_PROMPT"
    fi

    if [ ! -f "$RESOLVED_PROMPT_FILE" ]; then
      if [ -f "$SCRIPT_DIR/prompt.md" ]; then
        RESOLVED_PROMPT_FILE="$SCRIPT_DIR/prompt.md"
      else
        echo "Error: Prompt file '$RESOLVED_PROMPT_FILE' not found."
        update_status_json "failed" "Error: Prompt file '$RESOLVED_PROMPT_FILE' not found."
        exit 1
      fi
    fi

    # Set up credentials and environment for the active account
    if [ -n "$ACTIVE_KEY_VAR" ] && [ -n "$ACTIVE_KEY_VAL" ]; then
      export "$ACTIVE_KEY_VAR"="$ACTIVE_KEY_VAL"
      if [ "$ACTIVE_KEY_VAR" = "GOOGLE_API_KEY" ]; then
        export ANTIGRAVITY_API_KEY="$ACTIVE_KEY_VAL"
      elif [ "$ACTIVE_KEY_VAR" = "ANTIGRAVITY_API_KEY" ]; then
        export GOOGLE_API_KEY="$ACTIVE_KEY_VAL"
      fi
    fi

    # Load custom env configurations from JSON if available
    if [ "$HAS_JSON_ACCOUNTS" = "true" ]; then
      ENV_KEYS=$(jq -r ".accounts[$CURRENT_ACCT_INDEX].env | keys[] // empty" "$CONFIG_FILE" 2>/dev/null || echo "")
      for k in $ENV_KEYS; do
        v=$(jq -r ".accounts[$CURRENT_ACCT_INDEX].env.\"$k\"" "$CONFIG_FILE")
        export "$k"="$v"
        if [ "$k" = "GOOGLE_API_KEY" ]; then
          export ANTIGRAVITY_API_KEY="$v"
        elif [ "$k" = "ANTIGRAVITY_API_KEY" ]; then
          export GOOGLE_API_KEY="$v"
        fi
      done
    fi

    # Manage profile directory symlinking
    manage_profiles "$ACTIVE_NAME" "$ACTIVE_TOOL"

    echo "  Command: $TOOL_CMD"
    echo "  Input Method: $TOOL_INPUT_METHOD"
    echo "  Prompt File: $(basename "$RESOLVED_PROMPT_FILE")"
    echo "--------------------------------------------------------"

    # Execute agent tool based on the input method
    case "$TOOL_INPUT_METHOD" in
      stdin)
        OUTPUT=$(eval "$TOOL_CMD" < "$RESOLVED_PROMPT_FILE" 2>&1 | tee /dev/stderr) || true
        ;;
      file)
        OUTPUT=$(eval "$TOOL_CMD \"$RESOLVED_PROMPT_FILE\"" 2>&1 | tee /dev/stderr) || true
        ;;
      arg)
        PROMPT_CONTENT=$(cat "$RESOLVED_PROMPT_FILE")
        export RALPH_PROMPT_TEMP="$PROMPT_CONTENT"
        OUTPUT=$(eval "$TOOL_CMD \"\$RALPH_PROMPT_TEMP\"" 2>&1 | tee /dev/stderr) || true
        unset RALPH_PROMPT_TEMP
        ;;
      env)
        PROMPT_CONTENT=$(cat "$RESOLVED_PROMPT_FILE")
        export RALPH_PROMPT="$PROMPT_CONTENT"
        OUTPUT=$(eval "$TOOL_CMD" 2>&1 | tee /dev/stderr) || true
        unset RALPH_PROMPT
        ;;
      none)
        OUTPUT=$(eval "$TOOL_CMD" 2>&1 | tee /dev/stderr) || true
        ;;
    esac

    # Detect capacity limits or rate limit errors
    CAPACITY_EXHAUSTED=false
    if echo "$OUTPUT" | grep -E -i -q "rate limit|quota|ResourceExhausted|insufficient credit|credit limit|balance|over capacity|exceeded|429|exhausted|limit reached"; then
      CAPACITY_EXHAUSTED=true
    fi

    if [ "$CAPACITY_EXHAUSTED" = "true" ] && [ "$NUM_ACCOUNTS" -gt 1 ]; then
      # Mark limit hit in our states
      ACCT_LIMIT_HIT[$CURRENT_ACCT_INDEX]="true"
      
      CONSECUTIVE_SWITCHES=$((CONSECUTIVE_SWITCHES + 1))
      if [ "$CONSECUTIVE_SWITCHES" -ge "$NUM_ACCOUNTS" ]; then
        echo ""
        echo "Error: All configured accounts have exhausted their capacity. Loop aborted."
        update_status_json "failed" "All configured accounts have exhausted their capacity."
        exit 1
      fi

      CURRENT_ACCT_INDEX=$(( (CURRENT_ACCT_INDEX + 1) % NUM_ACCOUNTS ))
      echo ""
      echo "⚠ Capacity limit hit for '$ACTIVE_NAME'. Rotating to next account: '${ACCT_NAMES[$CURRENT_ACCT_INDEX]}'..."
      update_status_json "running" "Capacity limit hit on '$ACTIVE_NAME'. Rotating to '${ACCT_NAMES[$CURRENT_ACCT_INDEX]}'..."
      sleep 2
      continue
    fi

    # Success or normal failure, break out of retry loop
    break
  done
  
  # Check for completion signal in stdout
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks (detected via COMPLETE promise)!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    update_status_json "completed" "Ralph completed all tasks (detected via COMPLETE promise)!"
    exit 0
  fi

  # Check prd.json directly to see if all user stories have been marked as passing
  if [ -f "$PRD_FILE" ]; then
    INCOMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE" 2>/dev/null || echo "-1")
    if [ "$INCOMPLETE_COUNT" -eq 0 ]; then
      echo ""
      echo "Ralph completed all tasks (verified via $PRD_FILE)!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"
      update_status_json "completed" "Ralph completed all tasks (verified via $PRD_FILE)!"
      exit 0
    elif [ "$INCOMPLETE_COUNT" -eq -1 ]; then
      echo "Warning: Could not parse $PRD_FILE to verify passes status."
    fi
  fi
  
  echo "Iteration $i complete. Continuing..."
  update_status_json "running" "Iteration $i complete. Proceeding to iteration $((i + 1))..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
update_status_json "failed" "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
exit 1
