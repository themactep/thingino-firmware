#!/bin/bash
#
# Script to check for missing braces in C/C++ files
# Usage: ./scripts/check-braces.sh [file1] [file2] ... or ./scripts/check-braces.sh (for all files)
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check a single file
check_file() {
    local file="$1"
    local issues=0
    
    echo -e "${GREEN}Checking: $file${NC}"
    
    # Check for if statements without braces
    if grep -n "if\s*([^{]*)\s*[^{]" "$file" | grep -v "if.*{" > /dev/null; then
        echo -e "${RED}Missing braces after if statement:${NC}"
        grep -n "if\s*([^{]*)\s*[^{]" "$file" | grep -v "if.*{"
        issues=1
    fi
    
    # Check for while statements without braces
    if grep -n "while\s*([^{]*)\s*[^{]" "$file" | grep -v "while.*{" > /dev/null; then
        echo -e "${RED}Missing braces after while statement:${NC}"
        grep -n "while\s*([^{]*)\s*[^{]" "$file" | grep -v "while.*{"
        issues=1
    fi
    
    # Check for for statements without braces
    if grep -n "for\s*([^{]*)\s*[^{]" "$file" | grep -v "for.*{" > /dev/null; then
        echo -e "${RED}Missing braces after for statement:${NC}"
        grep -n "for\s*([^{]*)\s*[^{]" "$file" | grep -v "for.*{"
        issues=1
    fi
    
    # Check for else statements without braces
    if grep -n "else\s*[^{]" "$file" | grep -v "else.*{" | grep -v "else if" > /dev/null; then
        echo -e "${RED}Missing braces after else statement:${NC}"
        grep -n "else\s*[^{]" "$file" | grep -v "else.*{" | grep -v "else if"
        issues=1
    fi
    
    return $issues
}

# Main script
echo -e "${GREEN}Checking for missing braces in C/C++ files...${NC}"

total_issues=0

if [ $# -eq 0 ]; then
    # No arguments, check all C/C++ files
    files=$(find src -name "*.cpp" -o -name "*.hpp" -o -name "*.c" -o -name "*.h" 2>/dev/null)
else
    # Check specified files
    files="$@"
fi

for file in $files; do
    if [ -f "$file" ]; then
        check_file "$file"
        if [ $? -eq 1 ]; then
            total_issues=$((total_issues + 1))
        fi
    else
        echo -e "${YELLOW}Warning: File not found: $file${NC}"
    fi
done

if [ $total_issues -eq 0 ]; then
    echo -e "${GREEN}All files passed brace checks!${NC}"
    exit 0
else
    echo -e "${RED}Found brace issues in $total_issues file(s).${NC}"
    echo -e "${YELLOW}Please add braces around all control statements.${NC}"
    exit 1
fi
