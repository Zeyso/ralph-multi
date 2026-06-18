# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/

# Copy the prompt template for your AI tool of choice:
cp /path/to/ralph/prompt.md scripts/ralph/prompt.md    # For Amp
# OR
cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md    # For Claude Code

chmod +x scripts/ralph/ralph.sh
```

### Option 2: Install skills globally (Amp)

Copy the skills to your Amp or Claude config for use across all projects:

For AMP
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/
```

For Claude Code (manual)
```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Marketplace

Add the Ralph marketplace to Claude Code:

```bash
/plugin marketplace add snarktank/ralph
```

Then install the skills:

```bash
/plugin install ralph-skills@ralph-marketplace
```

Available skills after installation:
- `/prd` - Generate Product Requirements Documents
- `/ralph` - Convert PRDs to prd.json format

Skills are automatically invoked when you ask Claude to:
- "create a prd", "write prd for", "plan this feature"
- "convert this prd", "turn into ralph format", "create prd.json"

### Configure Amp auto-handoff (recommended)

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

## Workflow

### 1. Create a PRD

Use the PRD skill to generate a detailed requirements document:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph format

Use the Ralph skill to convert the markdown PRD to JSON:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

You can run Ralph with the built-in preset tools (Amp, Claude Code) or pass options to use any other coding agent (such as Antigravity, Codex, Aider, etc.).

```bash
# Using Amp (default preset)
./scripts/ralph/ralph.sh [max_iterations]

# Using Claude Code (preset)
./scripts/ralph/ralph.sh --tool claude [max_iterations]

# Using Antigravity (configured in ralph.config.json)
./scripts/ralph/ralph.sh --tool antigravity [max_iterations]

# Using a one-off custom agent command
./scripts/ralph/ralph.sh --tool custom --cmd "aider --message-file" --input-method file [max_iterations]
```

#### CLI Parameters

- `--tool <name>`: The AI agent tool to run. Presets are `amp` and `claude`. If customized in `ralph.config.json`, any tool name can be used.
- `--cmd <command>` / `--command <command>`: The command to execute (e.g. `antigravity-cli run`). Overrides the default or configured tool command.
- `--input-method <stdin|file|arg|env|none>`: How the prompt file content is passed to the command:
  - `stdin` (default): Pipes prompt content to standard input (`cmd < prompt.md`).
  - `file`: Appends the prompt file path as the last argument to the command (`cmd prompt.md`).
  - `arg`: Passes the prompt file content as the last argument to the command (`cmd "prompt content"`).
  - `env`: Stores the prompt file content in the `RALPH_PROMPT` environment variable.
  - `none`: Runs the command directly without passing prompt content.
- `--prompt-file <path>`: The prompt instructions file to pass. Defaults to `prompt.md`, `CLAUDE.md` (for Claude), or tool-specific files like `ANTIGRAVITY.md` / `CODEX.md` if they exist.
- `--config <path>`: Path to a custom configuration file (defaults to `ralph.config.json`).
- `[max_iterations]`: A numeric value specifying the max loop iterations (defaults to 10).

#### Configuration File (`ralph.config.json`)

You can create a `ralph.config.json` in the script directory to store default configuration settings and custom tool definitions:

```json
{
  "defaultTool": "amp",
  "maxIterations": 10,
  "tools": {
    "antigravity": {
      "cmd": "antigravity-cli run",
      "inputMethod": "file",
      "promptFile": "prompt.md"
    },
    "codex": {
      "cmd": "codex-agent --run",
      "inputMethod": "stdin",
      "promptFile": "prompt.md"
    }
  }
}
```

An example configuration is available in `ralph.config.json.example`.

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh AI instances (agent-agnostic, supports Amp, Claude, Antigravity, Codex, Aider, etc.) |
| `ralph.config.json` | Configuration file for tool execution commands, input methods, and defaults |
| `ralph.config.json.example` | Example configuration file showing custom agent settings |
| `prompt.md` | Prompt template for Amp and general custom agents |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings for future iterations |
| `skills/prd/` | Skill for generating PRDs (works with Amp and Claude Code) |
| `skills/ralph/` | Skill for converting PRDs to JSON (works with Amp and Claude Code) |
| `.claude-plugin/` | Plugin manifest for Claude Code marketplace discovery |
| `flowchart/` | Interactive visualization of how Ralph works |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

The `flowchart/` directory contains the source code. To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (Amp or Claude Code) with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

Ralph will exit the loop under two conditions:
1. All user stories in `prd.json` have `passes: true` (verified directly via `jq`).
2. The agent outputs `<promise>COMPLETE</promise>` in standard output.

This dual stop condition ensures Ralph works seamlessly with both custom external agents and built-in preset workflows.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying `prompt.md` (for Amp) or `CLAUDE.md` (for Claude Code) to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## Docker & Unraid Deployment

Ralph can be built and run inside a Docker container, making it easy to run automated development loops on systems like Unraid without installing CLI clients locally on your host.

### Docker Setup

1. **Build and Run via Docker Compose:**
   Create a `docker-compose.yml` (an example is in the repository root) and configure your environment variables:
   ```yaml
   version: "3.8"
   services:
     ralph:
       build: .
       environment:
         - AGENT_TOOL=amp # Select agent (amp, claude, antigravity, etc.)
         - MAX_ITERATIONS=10
         - GOOGLE_API_KEY=your_google_api_key
         - ANTHROPIC_API_KEY=your_anthropic_api_key
       volumes:
         # Mount your codebase folder containing your git repo
         - ./my-project:/workspace/project
         # Mount credential directories to persist auth between runs
         - ./config/amp:/root/.config/amp
         - ./config/claude:/root/.claude
   ```

2. **Launch the Container:**
   ```bash
   docker compose up --build
   ```

### Unraid Support

Ralph includes a dedicated Unraid template file under `templates/ralph.xml` to allow deployment via Unraid's Community Applications.

#### VM ISO-style PRD Selector
When configuring the Ralph container on Unraid, you can mount your project directory and mount a specific `prd.json` file independently using the built-in file selector:

1. **Project Path**: Map this to your project source code directory on your Unraid flash/appdata/array (e.g. `/mnt/user/appdata/projects/my-web-app`).
2. **PRD File**: Use the Unraid file browser to select the specific `prd.json` file you want the agent to execute for this run. It will be mounted directly into the workspace project directory.
3. **AI Agent Tool**: Set this variable (`AGENT_TOOL`) to specify which agent client to execute (e.g., `amp`, `claude`, `antigravity`, or `codex`).
4. **API Keys**: Provide the corresponding credentials (e.g., `GOOGLE_API_KEY` for Antigravity or `ANTHROPIC_API_KEY` for Claude) in the template fields.

When the container starts, it will configure Git safety directories, mount the files, and run the agent loop automatically, outputting progress to the container logs in real time.

## Account Rotation & Failover

Ralph supports configuring multiple accounts/keys for a single agent tool, or rotating between entirely different agent tools (e.g. from Claude to Antigravity) when capacity or rate limits are reached.

If a command fails and a rate limit or capacity warning (e.g. `rate limit`, `ResourceExhausted`, `quota exceeded`, `429`) is detected in the output, Ralph will log the exhaustion, switch to the next configured account, and retry execution in the same iteration.

### Configuration

You can configure accounts using environment variables or a `ralph.config.json` file.

#### Option A: Environment Variables (Recommended for Unraid)

1. Specify the list of active accounts as a comma-separated list in `AGENT_ACCOUNTS` (e.g. `claude-1,antigravity-1,claude-2`).
2. Provide numbered API keys matching the account suffixes:
   - `claude-1` looks for `ANTHROPIC_API_KEY_1` (falls back to `ANTHROPIC_API_KEY` if unset).
   - `claude-2` looks for `ANTHROPIC_API_KEY_2`.
   - `antigravity-1` looks for `GOOGLE_API_KEY_1` (falls back to `GOOGLE_API_KEY` or `ANTIGRAVITY_API_KEY` if unset).

#### Option B: JSON Configuration (`ralph.config.json`)

Define an `accounts` array in the JSON file. Each account has a `name`, a `tool`, and an `env` object defining the credentials variables:

```json
{
  "accounts": [
    {
      "name": "claude-personal",
      "tool": "claude",
      "env": {
        "ANTHROPIC_API_KEY": "sk-ant-..."
      }
    },
    {
      "name": "antigravity-work",
      "tool": "antigravity",
      "env": {
        "GOOGLE_API_KEY": "AIzaSy..."
      }
    }
  ]
}
```

### File-Based Session Profiles

For agents that authenticate via local files (like Claude Code or Antigravity's `agy`), Ralph automatically manages symlinks for directories named after your profiles:
- If a folder `$HOME/.claude_[account-name]` exists, Ralph will dynamically link it to `$HOME/.claude` when that account runs.
- If a folder `$HOME/.config/agy_[account-name]` exists, Ralph will dynamically link it to `$HOME/.config/agy` when that account runs.

This allows mounting multiple profiles in Docker to run separate accounts concurrently or sequentially without sharing sessions:
- `-v /mnt/user/appdata/ralph/claude_prof1:/root/.claude_claude-1`
- `-v /mnt/user/appdata/ralph/claude_prof2:/root/.claude_claude-2`

## Web Dashboard

Ralph includes a built-in, lightweight Web Dashboard served automatically on port `3000`. The dashboard displays real-time execution states, iteration counters, accounts status, and the current task progress.

### Features

- **Live Status Monitoring**: Displays current run state (Idle, Running, Completed, Failed).
- **Rotation Tracker**: Lists configured accounts (such as `claude-1`, `antigravity-1`) and marks which account is currently active, pending, or rate-limited.
- **PRD User Stories Progress**: Calculates completion percentage and lists all user stories, their Acceptance Criteria, and their passes status.
- **Console Log Stream**: Displays the scrollable tail of `progress.txt` for monitoring terminal logs directly in the browser.

### Unraid WebUI Integration

When running in Unraid, a click-through button labeled **WebUI** is automatically added to the container options. Clicking this button opens the dashboard immediately at `http://[Unraid-IP]:3000`. 

To access the Web UI:
1. Ensure port `3000` is mapped in the container configuration (the default is `3000`).
2. Click the container icon in the Unraid GUI and select **WebUI**.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
