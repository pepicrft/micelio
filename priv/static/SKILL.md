# Micelio & hif

Micelio is a minimalist git forge, and hif is its CLI client.

## Installing hif

hif is built with Zig. To build from source:

```bash
# Clone the micelio repository
git clone https://github.com/ruby/micelio.git
cd micelio/cli

# Build the CLI
zig build

# The binary will be at zig-out/bin/hif
# Move it to your PATH
cp zig-out/bin/hif /usr/local/bin/
```

## Authentication

Before using most commands, authenticate with the forge:

```bash
# Login via device flow (opens browser)
hif auth login

# Check authentication status
hif auth status

# Remove stored credentials
hif auth logout
```

## Project Management

```bash
# List projects in an organization
hif project list <organization>

# Create a new project
hif project create <organization> <handle> <name> [--description <desc>]

# Get project details
hif project get <organization> <handle>

# Update project fields
hif project update <organization> <handle> [--name <name>] [--description <desc>] [--new-handle <handle>]

# Delete a project
hif project delete <organization> <handle>
```

## Working with Content

```bash
# List files in a project
hif ls <account> <project> [--path prefix]

# Print file contents
hif cat <account> <project> <path>
```

## Workspaces

Create a local workspace to work on a project:

```bash
# Checkout a project (creates local workspace)
hif checkout <account>/<project> [--path dir]

# Show workspace changes
hif status

# Land workspace changes
hif land <goal>

# Write content from stdin to a file
hif write <path>
```

## Sessions

Sessions track work progress with notes and goals:

```bash
# Start a new session
hif session start <organization> <project> <goal>

# Show current session status
hif session status

# Add a note to the session
hif session note <message> [--role human|agent]

# Land the session (push to forge)
hif session land

# Abandon the current session
hif session abandon
```

## Quick Start

```bash
# 1. Authenticate
hif auth login

# 2. List available projects
hif project list micelio

# 3. Checkout a project
hif checkout micelio/myproject

# 4. Start a session
hif session start micelio myproject "Add feature X"

# 5. Make changes and add notes
echo "content" | hif write src/new_file.txt
hif session note "Added new file for feature X"

# 6. Land your changes
hif session land
```
