#!/bin/bash
# Ralph Container Entrypoint
# Automatically configures environment and launches the loop

echo "=========================================================="
# ASCII Art for a nice premium container look
echo "    ____           __      __      "
echo "   / __ \____ _   / /___  / /_     "
echo "  / /_/ / __ \`/  / / __ \/ __ \\    "
echo " / _, _/ /_/ /  / / /_/ / / / /    "
echo "/_/ |_|\\__,_/  /_/\\____/_/ /_/     "
echo "                                   "
echo " Autonomous AI Agent Loop Container"
echo "=========================================================="
echo ""

# Configuration variables from environment
AGENT_TOOL="${AGENT_TOOL:-amp}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
RALPH_ARGS="${RALPH_ARGS:-}"
KEEP_ALIVE="${KEEP_ALIVE:-false}"

# Verify we have a workspace project mounted
if [ ! -d "/workspace/project" ]; then
  echo "Error: No project mounted at /workspace/project."
  echo "Please mount your codebase directory to /workspace/project"
  echo "e.g. docker run -v \$(pwd):/workspace/project ralph-multi"
  exit 1
fi

# Set safe directory for git to avoid ownership/permission errors
git config --global --add safe.directory /workspace/project

# Change directory to project mount
cd /workspace/project

# Check if prd.json exists
if [ ! -f "prd.json" ]; then
  echo "Error: prd.json not found in the project root (/workspace/project/prd.json)."
  echo "Please mount or create a prd.json file."
  if [ "$KEEP_ALIVE" = "true" ]; then
    echo "KEEP_ALIVE is true, keeping container running for inspection..."
    exec tail -f /dev/null
  else
    exit 1
  fi
fi

# Print status check of tools
echo "Checking installed tools in path:"
for tool in amp claude agy; do
  if command -v "$tool" &>/dev/null; then
    echo "  [✓] $tool: $(command -v "$tool")"
  else
    echo "  [ ] $tool: Not found in path (some custom commands may still work)"
  fi
done
echo ""

# Start Dashboard Web Server
echo "Starting Dashboard Web Server on port 3000..."
node /workspace/server.js &
echo ""

echo "Launching Ralph loop..."
echo "  Agent:       $AGENT_TOOL"
echo "  Iterations:  $MAX_ITERATIONS"
echo "  Extra Args:  $RALPH_ARGS"
echo "----------------------------------------------------------"

# Run ralph.sh and capture exit code
/usr/local/bin/ralph.sh --tool "$AGENT_TOOL" $RALPH_ARGS "$MAX_ITERATIONS"
EXIT_CODE=$?

echo "----------------------------------------------------------"
echo "Ralph loop finished with exit code $EXIT_CODE."

# Keep container running if requested, otherwise exit
if [ "$KEEP_ALIVE" = "true" ]; then
  echo "KEEP_ALIVE is true. Keeping container alive for inspection..."
  exec tail -f /dev/null
else
  exit $EXIT_CODE
fi
