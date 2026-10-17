"""E1 compiler contract and adversarial package tests (no gameplay writes)."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('e1_compile', HERE / 'e1_compile.py') if (HERE / 'e1_compile.py').exists() else None
compiler = importlib.util.module_from_spec(SPEC) if SPEC else None
if compiler:
    SPEC.loader.exec_module(compiler)


class E1Contract(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(compiler, 'E1 compiler must exist before package publication')
        self.temp = tempfile.TemporaryDirectory(prefix='tongguan_e1_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'package'
        self.manifest = compiler.compile_lab(self.root, 'test_build')
        self.expected = self.manifest['compatibility'].copy()

    def write_manifest(self, value):
        compiler.save(self.root / 'presentation.package.json', value)

    def assert_code(self, code):
        with self.assertRaises(compiler.PackageError) as error:
            compiler.validate_package(self.root, self.expected)
        self.assertEqual(error.exception.code, code)

    def rewrite_data(self, path, value):
        compiler.save(self.root / path, value)
        for row in self.manifest['files']:
            if row['path'] == path:
                row['sha256'] = compiler.sha(self.root / path)
        self.write_manifest(self.manifest)

    def test_sparse_package_has_16_unique_children_and_parent(self):
        result = compiler.validate_package(self.root, self.expected)
        self.assertEqual(result['optional_missing'], ['terrain/fine_2_1.png.bin'])
        catalog = compiler.read(self.root / 'world.catalog.json')
        self.assertEqual(len(catalog['pages']), 21)
        fine = [p for p in catalog['pages'] if p['level'] == 2]
        self.assertEqual(len({p['texture_sha256'] for p in fine}), 16)
        self.assertTrue(any('lab.tree.cross_border' in p['object_ids'] for p in fine if p['x'] == 0))

    def test_missing_required_dependency_is_rejected(self):
        (self.root / 'instances/objects.json').unlink()
        self.assert_code('missing_file')

    def test_wrong_hash_is_rejected(self):
        with (self.root / 'terrain/fine_0_0.png.bin').open('ab') as file:
            file.write(b'corruption')
        self.assert_code('hash_mismatch')

    def test_unsupported_schema_is_rejected(self):
        self.manifest['schema_version'] = 2
        self.write_manifest(self.manifest)
        self.assert_code('unsupported_schema')

    def test_world_layout_and_graph_are_separate_compatibility_gates(self):
        for key in ['world_id', 'layout_version', 'graph_version', 'coordinate_sha256']:
            with self.subTest(key=key):
                wrong = self.expected.copy(); wrong[key] = 'wrong'
                with self.assertRaises(compiler.PackageError) as error:
                    compiler.validate_package(self.root, wrong)
                self.assertEqual(error.exception.code, 'incompatible_' + key)

    def test_outside_and_executable_paths_are_rejected(self):
        original = self.manifest['files'][0]['path']
        for path in ['../escape.json', '/absolute.json', 'C:/outside.json', 'a\\b.json', 'payload.gd']:
            with self.subTest(path=path):
                self.manifest['files'][0]['path'] = path
                self.write_manifest(self.manifest)
                self.assert_code('unsafe_path')
        self.manifest['files'][0]['path'] = original

    def test_duplicate_inventory_paths_are_rejected_before_indexing(self):
        self.manifest['files'].append(self.manifest['files'][0].copy())
        self.write_manifest(self.manifest)
        self.assert_code('duplicate_file_path')

    def test_duplicate_raw_objects_are_rejected_before_dictionary_projection(self):
        data = compiler.read(self.root / 'instances/objects.json')
        data['objects'].append(data['objects'][0].copy())
        self.rewrite_data('instances/objects.json', data)
        self.assert_code('duplicate_object_id')

    def test_record_id_and_source_key_must_agree(self):
        data = compiler.read(self.root / 'instances/objects.json')
        data['objects'][0]['source_key'] = 'another_object'
        self.rewrite_data('instances/objects.json', data)
        self.assert_code('source_key_mismatch')

    def test_relocation_changes_owner_without_changing_identity(self):
        item = compiler.read(self.root / 'instances/objects.json')['objects'][0]
        moved = compiler.relocate(item, [530, 0])
        self.assertEqual(moved['id'], item['id'])
        self.assertNotEqual(moved['owner'], item['owner'])
        self.assertEqual(item['position_m'], [-5, -5])
        self.assertEqual(item['owner'], [-1, -1])

    def test_raw_source_duplicate_is_not_silently_overwritten(self):
        snapshot = compiler.read(compiler.ROOT/'review-work/map_v02/e1_boundary/effective_snapshot.json')
        snapshot['raw_instance_ids'].append(snapshot['raw_instance_ids'][0])
        path=Path(self.temp.name)/'bad_snapshot.json';compiler.save(path,snapshot)
        with self.assertRaises(compiler.PackageError) as error:
            compiler.compile_snapshot(path,Path(self.temp.name)/'bad_package','bad')
        self.assertEqual(error.exception.code,'duplicate_raw_id')
        self.assertFalse((Path(self.temp.name)/'bad_package').exists())

    def test_source_key_mismatch_rejected_before_any_package_write(self):
        snapshot = compiler.read(compiler.ROOT/'review-work/map_v02/e1_boundary/effective_snapshot.json')
        snapshot['objects'][0]['source_key']='wrong'
        path=Path(self.temp.name)/'bad_snapshot.json';compiler.save(path,snapshot)
        with self.assertRaises(compiler.PackageError) as error:
            compiler.compile_snapshot(path,Path(self.temp.name)/'bad_package','bad')
        self.assertEqual(error.exception.code,'source_key_mismatch')
        self.assertFalse((Path(self.temp.name)/'bad_package').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
