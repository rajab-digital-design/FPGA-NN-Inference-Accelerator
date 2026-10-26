#!/usr/bin/env python3
"""Dependency-light checks for the public repository package."""
from __future__ import annotations
import csv
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    'README.md', 'LICENSE', 'docs/architecture.md', 'docs/implementation-scope.md', 'docs/results.md', 'docs/reproduction.md',
    'docs/fixed-point.md', 'docs/test-evidence.md', '.gitignore', '.gitattributes',
    'architecture-comparison.csv',
    'architectures/base-4mac/rtl/NN_Accelerator_4x8x1_DualPort.vhd',
    'architectures/pipeline-4mac/rtl/Output_Layer_1MAC_Pipelined.vhd',
    'architectures/one-hot-4mac/tb/tb_input_buffer_one_hot_equivalence.vhd',
    'architectures/address-replication-4mac/tb/tb_scheduler_address_replica_equivalence.vhd',
    'architectures/one-hot-4mac/reports/modelsim/EXP_ONEHOT_full_network_regression_transcript.txt',
    'architectures/address-replication-4mac/reports/modelsim/EXP_FANOUT_full_network_regression_transcript.txt',
    'architectures/address-replication-4mac/reports/ise/pipe_fanout_verbose.twr',
    'reference-model/matlab/analysis/compute_analysis.py',
    'reference-model/matlab/analysis/test_240_predictions_recomputed.csv',
    'reference-model/matlab/analysis/result_metrics.json',
]
errors: list[str] = []
for rel in REQUIRED:
    if not (ROOT / rel).is_file(): errors.append(f'Missing required file: {rel}')

# The standalone release must not contain localized or academic-only assets.
for p in ROOT.rglob('*'):
    rel = p.relative_to(ROOT).as_posix()
    if any('\u0600' <= ch <= '\u06ff' or '\u0750' <= ch <= '\u077f' or '\u08a0' <= ch <= '\u08ff' for ch in rel):
        errors.append(f'Non-English path detected: {rel}')
    low = rel.lower()
    if any(token in low for token in (('the' + 'sis'), ('defense' + '_handbook'), ('readme' + '_fa'), ('_' + 'fa.md'), ('_' + 'fa.txt'), ('_' + 'fa.csv'))):
        errors.append(f'Excluded academic/localized material detected: {rel}')

# Scan known text file types for Arabic-script text and university-specific references.
text_exts = {'.md', '.txt', '.vhd', '.csv', '.json', '.yml', '.yaml', '.py', '.m', '.do', '.bat', '.sh', '.dot', '.svg', '.xst', '.ucf', '.xise', '.prj', '.xml', '.diff', '.gitignore', '.gitattributes'}
academic_terms = ('the' + 'sis', 'uni' + 'versity', 'under' + 'graduate', 'super' + 'visor', 'defense' + ' handbook', 'student' + ' id')
academic_pattern = re.compile(r'\b(?:' + '|'.join(re.escape(w) for w in academic_terms) + r')\b', re.I)
text_count = 0
for p in ROOT.rglob('*'):
    if not p.is_file(): continue
    if p.suffix.lower() not in text_exts and p.name not in {'.gitignore', '.gitattributes'}: continue
    try: raw = p.read_text(encoding='utf-8')
    except UnicodeDecodeError: continue
    text_count += 1
    if any('\u0600' <= ch <= '\u06ff' or '\u0750' <= ch <= '\u077f' or '\u08a0' <= ch <= '\u08ff' for ch in raw):
        errors.append(f'Non-English text detected: {p.relative_to(ROOT)}')
    if p.resolve() != Path(__file__).resolve() and academic_pattern.search(raw):
        errors.append(f'Academic-specific reference detected: {p.relative_to(ROOT)}')

# Check relative Markdown links and local image paths.
link_re = re.compile(r'!?!?\[[^\]]*\]\(([^)]+)\)')
md_count = 0
link_count = 0
for md in ROOT.rglob('*.md'):
    md_count += 1
    raw = md.read_text(encoding='utf-8')
    raw = re.sub(r'^```.*?^```\s*', '', raw, flags=re.M | re.S)
    for match in link_re.finditer(raw):
        target = match.group(1).strip().split()[0].strip('<>')
        if not target or target.startswith(('http://', 'https://', 'mailto:', '#', 'data:')): continue
        local = target.split('#', 1)[0].split('?', 1)[0]
        if local and not (md.parent / local).resolve().exists():
            errors.append(f'Broken Markdown link: {md.relative_to(ROOT)} -> {target}')
        else: link_count += 1

expected = {
    'Base': ('17.432', '-0.932', '17', '967', '782', '1377', '6'),
    'Pipeline': ('16.084', '0.416', '19', '986', '849', '1406', '6'),
    'One-Hot': ('16.355', '0.145', '19', '1019', '911', '1410', '6'),
    'Fanout': ('15.104', '1.396', '19', '994', '853', '1419', '6'),
}
try:
    with (ROOT / 'architecture-comparison.csv').open(encoding='utf-8-sig', newline='') as f:
        rows = {row['arch']: row for row in csv.DictReader(f)}
    for arch, values in expected.items():
        if arch not in rows: errors.append(f'Missing comparison row: {arch}'); continue
        actual = tuple(rows[arch][k] for k in ('period','slack','cycles','slices','ff','lut','mult'))
        if actual != values: errors.append(f'Comparison values drifted for {arch}: {actual!r}')
except Exception as exc:
    errors.append(f'Cannot parse architecture comparison CSV: {exc}')

trace_checks = {
    'architectures/base-4mac/reports/historical/parallel_4mac_base.twr': '17.432ns',
    'architectures/pipeline-4mac/reports/historical/pipe_verbose.twr': '16.084ns',
    'architectures/one-hot-4mac/reports/ise/pipe_onehot_verbose.twr': '16.355ns',
    'architectures/address-replication-4mac/reports/ise/pipe_fanout_verbose.twr': '15.104ns',
}
for rel, needle in trace_checks.items():
    p = ROOT / rel
    if not p.is_file(): errors.append(f'Missing TRACE report: {rel}')
    elif needle not in p.read_text(encoding='utf-8', errors='replace'): errors.append(f'Expected timing metric {needle} not found in {rel}')

# Check the current SHA-256 manifest if present. The manifest excludes itself.
manifest = ROOT / 'SHA256SUMS.txt'
if manifest.exists():
    seen = set()
    for line in manifest.read_text(encoding='utf-8').splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2: errors.append(f'Malformed SHA-256 line: {line!r}'); continue
        digest, rel = parts
        rel = rel.lstrip('* ')
        seen.add(rel)
        p = ROOT / rel
        if not p.is_file(): errors.append(f'SHA-256 target missing: {rel}')
        elif hashlib.sha256(p.read_bytes()).hexdigest() != digest: errors.append(f'SHA-256 mismatch: {rel}')
    expected_paths = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and p != manifest}
    if expected_paths - seen: errors.append(f'SHA-256 manifest is missing {len(expected_paths - seen)} file(s)')
    if seen - expected_paths: errors.append(f'SHA-256 manifest has {len(seen - expected_paths)} unexpected entry/entries')

# Check the independent 240-row software analysis artifacts.
try:
    a = ROOT / 'reference-model/matlab/analysis'
    with (a / 'test_240_predictions_recomputed.csv').open(encoding='utf-8-sig', newline='') as f: predictions = list(csv.DictReader(f))
    if len(predictions) != 240: errors.append(f'Expected 240 software prediction rows, found {len(predictions)}')
    import json
    metrics = json.loads((a / 'result_metrics.json').read_text(encoding='utf-8'))
    if metrics.get('dataset', {}).get('sample_count') != 240: errors.append('result_metrics.json sample_count is not 240')
    if metrics.get('comparison_with_archived_csv', {}).get('all_fields_match') is not True: errors.append('The recomputed values are not recorded as a complete CSV match')
except Exception as exc:
    errors.append(f'Cannot validate the numerical analysis artifacts: {exc}')

print(f'Repository: {ROOT}')
print(f'Text files scanned: {text_count}; Markdown files checked: {md_count}; local links checked: {link_count}')
print(f'Required project files checked: {len(REQUIRED)}')
if errors:
    print(f'FAILED: {len(errors)} issue(s)')
    for issue in errors: print(f' - {issue}')
    sys.exit(1)
print('PASS: project files, English-only content, local links, timing metrics, numerical artifacts, and hashes are consistent.')
print('Tool note: this check does not compile RTL or rerun modelsim/Xilinx ISE. The Python numerical recomputation is run separately in CI.')
