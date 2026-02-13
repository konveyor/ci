#!/bin/bash
#
# Skill installation script for konveyor/ci repository
# Usage: ./skills/install.sh <skill-name>
#

set -e

SKILL_NAME="${1:-konveyor-nightly-updater}"
SKILL_FILE="skills/${SKILL_NAME}.skill"
SKILLS_DIR=".claude/skills"
SETTINGS_FILE=".claude/settings.local.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Installing skill: ${SKILL_NAME}"

# Check if skill file exists
if [ ! -f "$SKILL_FILE" ]; then
    echo -e "${RED}Error: Skill file not found: ${SKILL_FILE}${NC}"
    echo "Available skills:"
    ls -1 skills/*.skill 2>/dev/null | sed 's/skills\//  - /' | sed 's/\.skill$//' || echo "  (none)"
    exit 1
fi

# Create skills directory
echo -e "${YELLOW}Creating skills directory...${NC}"
mkdir -p "$SKILLS_DIR"

# Extract skill
echo -e "${YELLOW}Extracting skill...${NC}"
unzip -q -o -d "$SKILLS_DIR" "$SKILL_FILE"

# Update settings.local.json
if [ -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}Updating existing settings file...${NC}"

    # Check if enabledPlugins section exists
    if grep -q '"enabledPlugins"' "$SETTINGS_FILE"; then
        # Check if skill is already enabled
        if grep -q "\"${SKILL_NAME}\"" "$SETTINGS_FILE"; then
            echo -e "${GREEN}Skill already enabled in settings${NC}"
        else
            # Add skill to existing enabledPlugins
            # This is a simple approach - for complex JSON manipulation, use jq
            echo -e "${YELLOW}Note: Please manually add the following to enabledPlugins in ${SETTINGS_FILE}:${NC}"
            echo "  \"${SKILL_NAME}\": true"
        fi
    else
        echo -e "${YELLOW}Note: Please add the following to ${SETTINGS_FILE}:${NC}"
        echo '  "enabledPlugins": {'
        echo "    \"${SKILL_NAME}\": true"
        echo '  }'
    fi
else
    echo -e "${YELLOW}Creating settings file...${NC}"
    mkdir -p .claude
    cat > "$SETTINGS_FILE" << EOF
{
  "enabledPlugins": {
    "${SKILL_NAME}": true
  }
}
EOF
    echo -e "${GREEN}Created ${SETTINGS_FILE}${NC}"
fi

# Verify installation
echo ""
echo -e "${GREEN}✓ Skill installed successfully!${NC}"
echo ""
echo "Installed files:"
tree "$SKILLS_DIR/$SKILL_NAME" -L 2 2>/dev/null || find "$SKILLS_DIR/$SKILL_NAME" -maxdepth 2 -type f | sed 's/^/  /'

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo "You can now use the ${SKILL_NAME} skill in your Claude Code sessions."
