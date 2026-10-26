#!/usr/bin/env python3
"""Regenerate the repository-wide SHA-256 file manifest."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
manifest = ROOT / 'SHA256SUMS.txt'
files = sorted((p for p in ROOT.rglob('*') if p.is_file() and p != manifest), key=lambda p: p.relative_to(ROOT).as_posix().casefold())
manifest.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(ROOT).as_posix()}\n' for p in files), encoding='utf-8')
print(f'Wrote {len(files)} file hashes to {manifest.name}')
