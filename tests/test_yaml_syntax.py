#!/usr/bin/env bash
# tests/test_yaml_syntax.py - Validate all YAML files parse correctly
import glob
import sys
import yaml

def main():
    errors = []
    files = glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml')
    if not files:
        print('[WARN] No YAML files found')
        return 0
    for f in sorted(files):
        try:
            with open(f) as fh:
                yaml.safe_load(fh)
            print(f'  [OK]   {f}')
        except Exception as e:
            print(f'  [FAIL] {f} -- {e}')
            errors.append(f)
    if errors:
        print(f'\n{len(errors)} file(s) failed')
        return 1
    print(f'\nAll {len(files)} YAML files valid')
    return 0

if __name__ == '__main__':
    sys.exit(main())
