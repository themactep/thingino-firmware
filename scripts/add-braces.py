#!/usr/bin/env python3
"""
Script to automatically add braces around single-line control statements
"""

import re
import sys
import os

def add_braces_to_file(filepath):
    """Add braces to control statements in a single file"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        original_content = content
        
        # Pattern for if statements without braces
        # Matches: if (condition) statement;
        if_pattern = r'(\s*)(if\s*\([^{]*?\))\s*([^{\s][^;]*;)'
        content = re.sub(if_pattern, r'\1\2 {\n\1    \3\n\1}', content)
        
        # Pattern for else statements without braces
        # Matches: else statement;
        else_pattern = r'(\s*)(else)\s*([^{\s][^;]*;)'
        content = re.sub(else_pattern, r'\1\2 {\n\1    \3\n\1}', content)
        
        # Pattern for while statements without braces
        # Matches: while (condition) statement;
        while_pattern = r'(\s*)(while\s*\([^{]*?\))\s*([^{\s][^;]*;)'
        content = re.sub(while_pattern, r'\1\2 {\n\1    \3\n\1}', content)
        
        # Pattern for for statements without braces
        # Matches: for (init; condition; increment) statement;
        for_pattern = r'(\s*)(for\s*\([^{]*?\))\s*([^{\s][^;]*;)'
        content = re.sub(for_pattern, r'\1\2 {\n\1    \3\n\1}', content)
        
        # Only write if content changed
        if content != original_content:
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"Added braces to: {filepath}")
            return True
        else:
            print(f"No changes needed: {filepath}")
            return False
            
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

def main():
    if len(sys.argv) > 1:
        # Process specific files
        files = sys.argv[1:]
    else:
        # Process all C++ files in src directory
        files = []
        for root, dirs, filenames in os.walk('src'):
            for filename in filenames:
                if filename.endswith(('.cpp', '.hpp', '.c', '.h')):
                    files.append(os.path.join(root, filename))
    
    changed_files = 0
    for filepath in files:
        if os.path.exists(filepath):
            if add_braces_to_file(filepath):
                changed_files += 1
        else:
            print(f"File not found: {filepath}")
    
    print(f"\nProcessed {len(files)} files, modified {changed_files} files")

if __name__ == "__main__":
    main()
