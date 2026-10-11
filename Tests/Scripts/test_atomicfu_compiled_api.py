import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('atomicfu_compiled_checker', ROOT / 'Scripts/check_atomicfu_compiled_api.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class AtomicfuCompiledCheckerTests(unittest.TestCase):
    """Checker unit tests only. These snapshots are deliberately synthetic;
    passing them never counts as compiled atomicfu registration evidence.
    """
    def setUp(self):
        self.expected = json.loads(checker.EXPECTED.read_text())
        self.snapshot = {'schema_version': 1, 'lane': 'source', 'rows': [], 'extra_public_or_published_api_symbols': []}
        for index, row in enumerate(self.expected):
            actual = copy.deepcopy(row)
            actual.update(symbol_id=index, actual_kind=checker.KINDS.get(row['kind'], row['kind']),
                          imported_library=False, mutable=' var ' in row['signature'])
            self.snapshot['rows'].append(actual)

    def test_control_dataset_is_only_a_checker_control(self):
        self.assertEqual(checker.validate(self.expected, self.snapshot), [])

    def test_wrong_object_kind_is_rejected(self):
        row = next(r for r in self.snapshot['rows'] if r['kind'] == 'object')
        row['actual_kind'] = 'class'
        self.assertTrue(any('actual_kind' in p for p in checker.validate(self.expected, self.snapshot)))

    def test_nullable_reference_type_mismatch_is_rejected(self):
        row = next(r for r in self.snapshot['rows'] if r['return_type'] and '#0?' in r['return_type'])
        row['return_type'] = row['return_type'].replace('#0?', '#0')
        self.assertTrue(any('return_type' in p for p in checker.validate(self.expected, self.snapshot)))

    def test_error_level_and_binary_retention_are_not_name_only(self):
        row = next(r for r in self.snapshot['rows'] if r['api_symbol'] == 'kotlinx.atomicfu.locks/ExperimentalThreadBlockingApi')
        for ann in row['annotations']:
            if ann['name'] == 'RequiresOptIn':
                ann['arguments'] = ['level=RequiresOptIn.Level.WARNING']
        self.assertTrue(any('semantic annotation' in p for p in checker.validate(self.expected, self.snapshot)))

    def test_missing_published_internal_identity_is_rejected(self):
        index = next(i for i,r in enumerate(self.snapshot['rows']) if r['visibility'] == 'internal')
        self.snapshot['rows'].pop(index)
        self.assertTrue(checker.validate(self.expected, self.snapshot))

    def test_duplicate_compiler_symbol_and_extra_api_are_rejected(self):
        self.snapshot['rows'][1]['symbol_id'] = self.snapshot['rows'][0]['symbol_id']
        self.snapshot['extra_public_or_published_api_symbols'] = ['kotlinx.atomicfu.AtomicInt.load']
        problems = checker.validate(self.expected, self.snapshot)
        self.assertTrue(any('distinct compiler symbols' in p for p in problems))
        self.assertTrue(any('unexpected' in p for p in problems))

    def test_default_parameter_loss_is_rejected(self):
        row = next(r for r in self.snapshot['rows'] if True in r['parameter_has_defaults'])
        row['parameter_has_defaults'] = [False] * len(row['parameter_has_defaults'])
        self.assertTrue(any('parameter_has_defaults' in p for p in checker.validate(self.expected, self.snapshot)))

    def test_library_lane_keeps_binary_optional_expectation(self):
        self.snapshot['lane'] = 'library'
        for row in self.snapshot['rows']:
            row['imported_library'] = True
            row['annotations'] = [a for a in row['annotations'] if a['name'] not in checker.SOURCE_ONLY]
        self.assertEqual(checker.validate(self.expected, self.snapshot), [])
        row = next(r for r in self.snapshot['rows'] if r['api_symbol'] == 'kotlinx.atomicfu/OptionalJsName')
        row['annotations'] = [a for a in row['annotations'] if a['name'] != 'OptionalExpectation']
        self.assertTrue(any('OptionalExpectation' in p for p in checker.validate(self.expected, self.snapshot)))

    def test_generic_bound_loss_is_rejected(self):
        row = next(r for r in self.snapshot['rows'] if r['type_parameter_bounds'])
        row['type_parameter_bounds'] = ['kotlin.Any']
        self.assertTrue(any('type_parameter_bounds' in p for p in checker.validate(self.expected, self.snapshot)))


if __name__ == '__main__':
    unittest.main()
