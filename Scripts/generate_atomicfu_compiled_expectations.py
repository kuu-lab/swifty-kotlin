#!/usr/bin/env python3
"""Generate Native compiler expectations from the independent pinned KLIB ledger.

This generator never reads proposed Kotlin implementation headers or runtime
bodies. Running it is inventory preparation, not compiler/operation validation.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / 'docs/atomicfu-0.33.0/reference/atomicfu.common-native.declarations.json'
OUTPUT = ROOT / 'Tests/CompilerCoreTests/Fixtures/Atomicfu/native-api-150.json'


def split_types(text):
    result, start, depth = [], 0, 0
    for index, char in enumerate(text):
        if char == '<': depth += 1
        if char == '>': depth -= 1
        if char == ',' and depth == 0:
            result.append(text[start:index].strip())
            start = index + 1
    if text.strip(): result.append(text[start:].strip())
    return result


def normalize_type(text):
    text = text.split(' = ', 1)[0].replace('/', '.').replace(' ', '')
    return re.sub(r'#([A-Z])', lambda m: '#' + str(ord(m[1]) - ord('A')), text)


def expected_rows(ledger):
    rows = []
    for record in ledger['declarations']:
        if record['scope'] != 'common-native': continue
        annotations = []
        for source in record['source_provenance']:
            if source['evidence_status'] != 'verified-pinned-source':
                raise ValueError('Native annotation evidence is unavailable')
            for ann in source['annotation_records']:
                fact = {'name': ann['name'], 'arguments': [
                    ((arg['name'] + '=') if arg['name'] else '') + arg['expression']
                    for arg in ann['arguments']]}
                if fact not in annotations: annotations.append(fact)
        row = {key: record[key] for key in ('api_identity', 'api_symbol', 'kind', 'signature')}
        row.update(visibility=record['kotlin_visibility'], annotations=annotations,
                   parameter_types=[], receiver_type=None, return_type=None)
        signature = record['signature']
        parameter_text = ''
        if record['kind'] in ('function', 'constructor'):
            tail = signature[signature.index('fun ') + 4:] if record['kind'] == 'function' else signature.split('constructor ', 1)[1]
            if tail.startswith('<#'):
                depth = 0
                for index, char in enumerate(tail):
                    if char == '<': depth += 1
                    elif char == '>':
                        depth -= 1
                        if depth == 0:
                            tail = tail[index + 1:].strip()
                            break
            if tail.startswith('('):
                closing = tail.index(')')
                row['receiver_type'] = normalize_type(tail[1:closing])
                tail = tail[closing + 2:]
            opening, closing = tail.index('('), tail.rfind(')')
            parameter_text = tail[opening + 1:closing]
            row['parameter_types'] = [normalize_type(t) for t in split_types(parameter_text)]
            row['return_type'] = normalize_type(tail[closing + 2:].strip()) if tail[closing + 1:].startswith(':') else 'kotlin.Unit'
        row['is_inline'] = ' inline fun ' in ' ' + signature + ' '
        row['parameter_has_defaults'] = [' = ...' in t for t in split_types(parameter_text)]
        row['type_parameter_bounds'] = [normalize_type(t) for _, t in re.findall(r'#([A-Z]): ([^>,]+\??)', signature)]
        rows.append(row)
    if len(rows) != 150 or len({row['api_identity'] for row in rows}) != 150:
        raise ValueError('expected 150 unique common/Native identities')
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ledger', type=Path, default=LEDGER)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    content = (json.dumps(expected_rows(json.loads(args.ledger.read_text())), indent=2) + '\n').encode()
    if args.check:
        if not args.output.exists() or args.output.read_bytes() != content:
            print('FAIL: compiled expectations are stale')
            return 1
    else:
        args.output.write_bytes(content)
    print('PASS: pinned Native expectation generation (150 identities; not compiled validation)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
