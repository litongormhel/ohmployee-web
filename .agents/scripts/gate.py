#!/usr/bin/env python3
import json
import subprocess
import sys

def main():
    # Run the project lint suite
    result = subprocess.run(["npm", "run", "lint"], capture_output=True, text=True)

    if result.returncode != 0:
        output = {
            "decision": "continue",
            "reason": f"Verification gate FAILED. Lint must pass before stopping:\n{result.stderr or result.stdout}"
        }
        print(json.dumps(output))
        sys.exit(0)

    # Green: allow stop
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

if __name__ == "__main__":
    main()
