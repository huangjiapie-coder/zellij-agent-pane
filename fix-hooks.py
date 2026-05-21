#!/usr/bin/env python3
"""Fix corrupted hooks structure in settings.json

The issue was that SubagentStart and SubagentStop keys were initialized as
objects instead of arrays in some deployments.

Expected structure:
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [...]
      }
    ],
    "SubagentStop": [...]
  }
}

Usage: python fix-hooks.py [settings_path]
"""

import json
import sys
from pathlib import Path

def fix_hooks_structure(settings_path: str) -> bool:
    """Fix hooks structure in settings.json file."""
    try:
        with open(settings_path, 'r', encoding='utf-8-sig') as f:
            settings = json.load(f)
    except FileNotFoundError:
        print(f"Error: settings.json not found at {settings_path}")
        return False
    except json.JSONDecodeError as e:
        print(f"Error: settings.json is not valid JSON: {e}")
        return False

    if 'hooks' not in settings:
        print("Info: No hooks key in settings.json")
        return True

    hooks = settings['hooks']

    # Ensure hooks is an object (dict)
    if not isinstance(hooks, dict):
        print(f"Error: hooks is not a dict, it's a {type(hooks).__name__}")
        return False

    # Fix SubagentStart and SubagentStop to be arrays
    fixed = False
    for event_name in ['SubagentStart', 'SubagentStop']:
        if event_name not in hooks:
            hooks[event_name] = []
            print(f"  Added missing: {event_name} = []")
            fixed = True
        elif not isinstance(hooks[event_name], list):
            # Convert to array
            original_value = hooks[event_name]
            hooks[event_name] = [original_value] if original_value else []
            print(f"  Fixed {event_name}: {type(original_value).__name__} → []")
            fixed = True

    # Clean up hooks that are not SubagentStart or SubagentStop
    for key in list(hooks.keys()):
        if key not in ['SubagentStart', 'SubagentStop']:
            print(f"  Removed unexpected key: {key}")
            del hooks[key]
            fixed = True

    if fixed:
        # Backup
        bak_path = settings_path + '.fix-backup'
        with open(bak_path, 'w', encoding='utf-8') as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
        print(f"  Backup saved to: {bak_path}")

        # Write fixed version
        with open(settings_path, 'w', encoding='utf-8') as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
        print(f"  Fixed: {settings_path}")
        print(f"  SubagentStart hooks: {len(hooks.get('SubagentStart', []))}")
        print(f"  SubagentStop hooks: {len(hooks.get('SubagentStop', []))}")

        # Validate
        try:
            with open(settings_path, 'r', encoding='utf-8') as f:
                json.load(f)
            print("  ✓ settings.json is valid JSON")
            return True
        except json.JSONDecodeError as e:
            print(f"  ✗ settings.json is still invalid: {e}")
            # Restore from backup
            import shutil
            shutil.copy2(bak_path, settings_path)
            print(f"  Restored from backup")
            return False
    else:
        print("  No changes needed")
        return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        settings_path = Path.home() / '.claude' / 'settings.json'
    else:
        settings_path = sys.argv[1]

    print(f"Fixing hooks structure in: {settings_path}")
    print()

    if fix_hooks_structure(str(settings_path)):
        print("\n✓ Success!")
        sys.exit(0)
    else:
        print("\n✗ Failed!")
        sys.exit(1)
