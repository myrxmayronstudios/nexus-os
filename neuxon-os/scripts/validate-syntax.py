#!/usr/bin/env python3
"""
validate-syntax.py — Validates all shell scripts and configurations in Neuxon OS.
Checks:
  1. No TODO, FIXME, PLACEHOLDER, or stub ellipses
  2. Balanced if/fi, case/esac, for/while/done control blocks
  3. Proper shebang and non-empty files
"""

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

def get_script_files():
    scripts = []
    for dirpath, dirs, files in os.walk(ROOT):
        if '.git' in dirpath:
            continue
        for f in files:
            fp = os.path.join(dirpath, f)
            if f.endswith('.sh') or f in ['neuxon-control', 'neuxon-hud', 'autostart']:
                scripts.append(fp)
    return scripts

def strip_strings(line):
    # Remove escaped quotes first
    s = re.sub(r'\\"', '', line)
    s = re.sub(r"\\'", '', s)
    # Remove double-quoted strings
    s = re.sub(r'"[^"]*"', '""', s)
    # Remove single-quoted strings
    s = re.sub(r"'[^']*'", "''", s)
    return s

def validate_script(path):
    rel = os.path.relpath(path, ROOT)
    errors = []
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    if not lines:
        errors.append("File is empty!")
        return errors

    # Check shebang
    first_line = lines[0].strip()
    if not first_line.startswith('#!'):
        errors.append(f"Missing shebang on line 1: '{first_line}'")

    if_stack = 0
    case_stack = 0
    loop_stack = 0
    in_heredoc = False
    heredoc_tag = ''

    for idx, raw in enumerate(lines, 1):
        line = raw.strip()

        # Check for placeholders
        if re.search(r'\b(TODO|FIXME|PLACEHOLDER)\b', line, re.I):
            errors.append(f"Line {idx}: Contains placeholder: {line}")
        if line == '...':
            errors.append(f"Line {idx}: Contains ellipsis stub: {line}")

        if in_heredoc:
            if line == heredoc_tag:
                in_heredoc = False
                heredoc_tag = ''
            continue

        # Detect heredoc start
        m = re.search(r'<<\s*[\'"]?([A-Za-z0-9_-]+)[\'"]?', line)
        if m:
            in_heredoc = True
            heredoc_tag = m.group(1)
            line = line[:m.start()].strip()

        # Skip comment lines
        if line.startswith('#'):
            continue

        # Strip inline comment
        c_idx = line.find('#')
        if c_idx >= 0 and line[c_idx-1:c_idx] != '$':
            line = line[:c_idx].strip()

        # Strip string literals so words like "for", "while", "if" inside quotes aren't counted
        line = strip_strings(line)

        words = line.split()
        for w in words:
            clean_w = w.strip(';(){}|&!')
            if clean_w == 'if':
                if_stack += 1
            elif clean_w == 'fi':
                if_stack -= 1
            elif clean_w == 'case':
                case_stack += 1
            elif clean_w == 'esac':
                case_stack -= 1
            elif clean_w in ['for', 'while', 'until']:
                loop_stack += 1
            elif clean_w == 'done':
                loop_stack -= 1

    if if_stack != 0:
        errors.append(f"Unbalanced if/fi statements (delta={if_stack})")
    if case_stack != 0:
        errors.append(f"Unbalanced case/esac statements (delta={case_stack})")
    if loop_stack != 0:
        errors.append(f"Unbalanced for/while/done statements (delta={loop_stack})")

    return errors

def main():
    scripts = get_script_files()
    print(f"Auditing {len(scripts)} shell scripts in {ROOT}...")
    all_ok = True

    for s in sorted(scripts):
        rel = os.path.relpath(s, ROOT)
        errs = validate_script(s)
        if errs:
            all_ok = False
            print(f"❌ {rel}:")
            for e in errs:
                print(f"    - {e}")
        else:
            print(f"✓ {rel} (OK)")

    if all_ok:
        print("\nAll shell scripts validated successfully with zero errors!")
        sys.exit(0)
    else:
        print("\nValidation failed!")
        sys.exit(1)

if __name__ == '__main__':
    main()
