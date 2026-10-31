#!/usr/bin/env python3
"""Fail when a farm DLL lost Wine's delay imports (upstream issue #495).

For every DLL in <farm-dir> whose Wine module Makefile.in
(wine/dlls/<name>/Makefile.in) has a DELAYIMPORTS line, resolve each entry
to its owner file (the MODULE line of another wine/dlls Makefile.in, via
IMPORTLIB, e.g. winspool -> winspool.drv) and assert it is NOT in the PE's
regular import table (PE class from tools/check-wine-media-dlls.py). lld
drops delay imports a module never calls, so absence from the delay table
alone is not a violation.

Default-list modules (LIST_DEFAULT=1 build-modules.sh) keep plain imports
(Rockstar launcher NoExec per #271; plain wmvcore/winegstreamer for the
media gate, cf. PR #496) and are only flagged if a delay entry shows up in
both tables.

Prints a one-line summary; exits non-zero on any violation.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))

import importlib.util

spec = importlib.util.spec_from_file_location(
    'wine_pe', ROOT / 'tools/check-wine-media-dlls.py')
wine_pe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wine_pe)
PE = wine_pe.PE
SUFFIXES = ('.dll', '.drv', '.cpl', '.ocx', '.ax', '.acm')


def module_index():
    """Map installed file name -> (directory, delay-import owner file names)."""
    owners = {}
    by_lib = {}
    for makefile in (ROOT / 'wine' / 'dlls').glob('*/Makefile.in'):
        text = makefile.read_text(errors='replace')
        match = re.search(r'^MODULE\s*=\s*(\S+)', text, re.M)
        if match:
            owners[match.group(1).lower()] = makefile.parent.name
            lib = re.search(r'^IMPORTLIB\s*=\s*(\S+)', text, re.M)
            if lib:
                by_lib[lib.group(1).lower()] = match.group(1).lower()
    by_dir = {directory: file for file, directory in owners.items()}
    index = {}
    for file, directory in owners.items():
        text = (ROOT / 'wine' / 'dlls' / directory / 'Makefile.in').read_text(errors='replace')
        delay = re.search(r'^DELAYIMPORTS\s*=\s*(.*)$', text, re.M)
        if delay and delay.group(1).split():
            entries = [by_lib.get(entry.lower(),
                                  by_dir.get(entry.lower(), entry.lower() + '.dll'))
                       for entry in delay.group(1).split()]
            index[file] = (directory, entries)
    return index, owners


def main():
    if len(sys.argv) > 2:
        print(f'usage: {Path(sys.argv[0]).name} [<farm-dir>]', file=sys.stderr)
        return 2
    farm = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'app/Madeira/arm64ec-windows'
    import os
    env = dict(os.environ, LIST_DEFAULT='1')
    out = subprocess.run(['bash', str(ROOT / 'build/wine-pe/build-modules.sh')],
                         capture_output=True, text=True, check=True, env=env).stdout.split()
    undelayed_dirs = set(out)
    index, _ = module_index()
    checked, expected_plain, violations = 0, 0, []
    for path in sorted(farm.iterdir(), key=lambda p: p.name.lower()):
        if path.suffix.lower() not in SUFFIXES or not path.is_file():
            continue
        found = index.get(path.name.lower())
        if found is None:
            continue
        directory, delayed = found
        checked += 1
        try:
            pe = PE(path)
        except ValueError as error:
            violations.append(f'{path.name}: unreadable PE ({error})')
            continue
        regular = {dep.lower() for dep in pe.imports()}
        late = {dep.lower() for dep in pe.imports(delayed=True)}
        if directory in undelayed_dirs:
            # UNDELAY skips a default-list module unless every delay dep is
            # in the farm or the same run, so some committed ones legitimately
            # keep delays; and lld drops delay imports a module never calls.
            # Only a delay entry that became a regular import proves this
            # script rebuilt the module with UNDELAY.
            expected_plain += 1
            for want in delayed:
                if want in late and want in regular:
                    violations.append(
                        f'{path.name}: {want} must be a plain import '
                        f'(undelayed default; delay=[True] regular=[True])')
            continue
        for want in delayed:
            if want in regular:
                violations.append(
                    f'{path.name}: {want} delay-imported by wine/dlls/{directory} '
                    f'is delay=[{want in late}] regular=[True]')
    detail = f': {"; ".join(violations)}' if violations else ''
    print(f'{farm}: {checked} DLLs with DELAYIMPORTS '
          f'({expected_plain} undelayed default), {len(violations)} violations{detail}')
    return 1 if violations else 0


if __name__ == '__main__':
    raise SystemExit(main())
