# Konveyor CI Skills

This directory contains Claude Code skills for working with the Konveyor CI repository.

## Installation Convention

All skills in this repository can be installed using the standard installation script:

```bash
./skills/install.sh <skill-name>
```

For example:
```bash
./skills/install.sh konveyor-nightly-updater
```

The installation script will:
- Extract the skill to `.claude/skills/`
- Configure `.claude/settings.local.json` to enable the skill
- Verify the installation

**First-time setup:** If you don't have a `.claude/settings.local.json` file, the script will create one for you.

## Available Skills

### konveyor-nightly-updater.skill

Automates updating nightly CI workflows when a new Konveyor release is created.

**Use when:** Adding a new release nightly (e.g., release-0.9) and removing old releases (2 versions back).

**Example prompts:**
- "Update nightlies for release-0.9"
- "Add nightly for release-0.10 and remove release-0.8"

**What it does:**

**Automated changes in konveyor/ci:**
- Analyzes current releases and calculates what to add/remove
- Calculates cron schedules automatically (10 min after previous release)
- Creates new nightly workflow file
- Updates global-ci.yml with conditional blocks (both API and UI jobs)
- Updates README.md badge rows
- Deletes old nightly workflow file

**With your approval (shows full content first):**
- **CI issue**: Shows complete issue body, asks permission to create
- **CI PR**: Shows complete PR body, asks permission to create
- **Test repo issues**: Shows each issue separately, asks permission for each
  - go-konveyor-tests issue (update tier workflows)
  - kantra-cli-tests issue (add nightly workflow)

**Key feature:** You see the EXACT content before anything is created!

## Skill Contents

Each `.skill` file is a packaged set of:
- **Scripts** - Helper tools for analysis and validation
- **Templates** - File templates for workflows and documentation
- **References** - Detailed pattern documentation
- **Instructions** - Step-by-step workflow guidance

You can extract and explore the contents by unzipping the `.skill` file (it's just a zip file with a different extension).

## Contributing

To create or update skills for this repository:

1. Follow the [Claude Code skill creation guide](https://docs.anthropic.com/claude/docs/create-a-skill)
2. Test the skill thoroughly
3. Package it using the skill packaging tools
4. Add it to this `skills/` directory
5. Update this README with details about the new skill
