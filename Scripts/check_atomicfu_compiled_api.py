#!/usr/bin/env python3
"""Compare an actual Swift Sema snapshot against the pinned 150 Native ABI rows.

No declarations are synthesized here. Missing snapshots are errors; a copied
fixture or mock inventory is not accepted as evidence of compiler execution.
The caller must separately retain successful Swift test exits and input hashes.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = ROOT / 'Tests/CompilerCoreTests/Fixtures/Atomicfu/native-api-150.json'
SOURCE_ONLY = {'Suppress', 'OptIn'}
KINDS = {'annotation_class': 'annotationClass'}


def validate(expected, snapshot):
    problems = []
    lane = snapshot.get('lane')
    if snapshot.get('schema_version') != 1 or lane not in ('source', 'library'):
        problems.append('snapshot schema/lane is invalid')
    if len(expected) != 150 or len({r['api_identity'] for r in expected}) != 150:
        problems.append('pinned expectations must have 150 distinct Native identities')
    rows = snapshot.get('rows', [])
    if len(rows) != 150 or len({r.get('symbol_id') for r in rows}) != 150:
        problems.append('actual snapshot must have 150 distinct compiler symbols')
    actual = {r.get('api_identity'): r for r in rows}
    if len(actual) != len(rows):
        problems.append('actual snapshot has duplicate ABI identities')
    expected_ids = {r['api_identity'] for r in expected}
    if set(actual) != expected_ids:
        problems.append(f'identity mismatch: missing={sorted(expected_ids - set(actual))}, extra={sorted(set(actual) - expected_ids)}')
    if snapshot.get('extra_public_or_published_api_symbols') != []:
        problems.append('unexpected or unrecorded public/PublishedApi symbols')
    for expected_row in expected:
        identity = expected_row['api_identity']
        row = actual.get(identity)
        if row is None:
            continue
        comparisons = [('visibility', expected_row['visibility']),
                       ('actual_kind', KINDS.get(expected_row['kind'], expected_row['kind'])),
                       ('imported_library', lane == 'library'),
                       ('type_parameter_bounds', expected_row['type_parameter_bounds'])]
        if expected_row['kind'] in ('function', 'constructor'):
            comparisons.extend([('parameter_types', expected_row['parameter_types']),
                                ('parameter_has_defaults', expected_row['parameter_has_defaults'])])
        if expected_row['kind'] == 'function':
            comparisons.extend([('return_type', expected_row['return_type']),
                                ('receiver_type', expected_row['receiver_type']),
                                ('is_inline', expected_row['is_inline'])])
        if expected_row['kind'] == 'property':
            comparisons.append(('mutable', ' var ' in expected_row['signature']))
        for field, value in comparisons:
            if row.get(field) != value:
                problems.append(f'{identity}: {field}: expected={value!r} actual={row.get(field)!r}')
        if lane == 'library' and any(a['name'].split('.')[-1] in SOURCE_ONLY for a in row.get('annotations', [])):
            problems.append(f'{identity}: SOURCE annotation leaked into imported metadata')
        for annotation in expected_row['annotations']:
            name = annotation['name']
            if lane == 'library' and name in SOURCE_ONLY:
                continue
            matches = [r for r in row.get('annotations', []) if r['name'].split('.')[-1] == name]
            if not any(all(arg in item.get('arguments', []) for arg in annotation['arguments']) for item in matches):
                problems.append(f'{identity}: missing exact semantic annotation {annotation!r}')
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected', type=Path, default=EXPECTED)
    parser.add_argument('--snapshot', required=True, type=Path)
    args = parser.parse_args()
    expected = json.loads(args.expected.read_text())
    snapshot = json.loads(args.snapshot.read_text())
    problems = validate(expected, snapshot)
    if problems:
        for problem in problems:
            print('FAIL', problem)
        return 1
    print(f'PASS pinned Native API: {snapshot["lane"]}: 150 distinct identities / 142 public / 8 PublishedApi internal')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
