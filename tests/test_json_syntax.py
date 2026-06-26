#!/usr/bin/env python3
# tests/test_json_syntax.py - Validate all JSON configs parse correctly
import glob
import json
import sys

def main():
    errors = []
    files = glob.glob('configs/*.json')
    if not files:
        print('[WARN] No JSON files found')
        return 0
    for f in sorted(files):
        try:
            with open(f) as fh:
                json.load(fh)
            print(f'  [OK]   {f}')
        except Exception as e:
            print(f'  [FAIL] {f} -- {e}')
            errors.append(f)
    if errors:
        print(f'\n{len(errors)} file(s) failed')
        return 1
    print(f'\nAll {len(files)} JSON files valid')
    return 0

if __name__ == '__main__':
    sys.exit(main())
