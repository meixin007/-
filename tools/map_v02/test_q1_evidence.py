"""Evidence cannot discard spikes, silently accept missing VRAM, or publish partial builds."""
import importlib,importlib.util,sys,tempfile,unittest
from pathlib import Path

class Q1Evidence(unittest.TestCase):
    def module(self):
        self.assertIsNotNone(importlib.util.find_spec('q1_evidence'),'Q1 evidence recorder not implemented')
        return importlib.import_module('q1_evidence')
    def test_every_long_frame_retained(self):
        m=self.module();r=m.frame_summary([8]*96+[34,51,101,900])
        self.assertEqual(r['frames'],100);self.assertEqual(r['over_33ms'],4);self.assertEqual(r['over_50ms'],3);self.assertEqual(r['over_100ms'],2);self.assertEqual(r['max_ms'],900);self.assertFalse(r['budget_passed'])
    def test_empty_and_invalid_measurements_fail(self):
        m=self.module()
        for values in [[],[float('nan')],[0],[-2]]:
            with self.assertRaises(ValueError):m.frame_summary(values)
    def test_gpu_unavailable_is_not_zero(self):
        m=self.module();r=m.memory_summary([dict(private_bytes=100,gpu_dedicated_bytes=None)])
        self.assertIsNone(r['gpu_peak_bytes']);self.assertFalse(r['gpu_budget_verified'])
    def test_no_incomplete_build_activation(self):
        m=self.module()
        with tempfile.TemporaryDirectory(prefix='tongguan_q1_') as folder:
            root=Path(folder);m.write_version(root,'old',{'one.bin':b'old'})
            m.activate(root,'old');before=(root/'active.json').read_bytes()
            with self.assertRaises(ValueError):m.activate(root,'missing')
            self.assertEqual((root/'active.json').read_bytes(),before)
    def test_windows_pointer_failure_preserves_old(self):
        m=self.module()
        with tempfile.TemporaryDirectory(prefix='tongguan_q1_') as folder:
            root=Path(folder);m.write_version(root,'old',{'one.bin':b'old'});m.write_version(root,'new',{'one.bin':b'new'});m.activate(root,'old');before=(root/'active.json').read_bytes()
            for fault in ['before_replace','disk_full']:
                with self.assertRaises(OSError):m.activate(root,'new',fault=fault)
                self.assertEqual((root/'active.json').read_bytes(),before)
            m.activate(root,'new');self.assertNotEqual((root/'active.json').read_bytes(),before);m.rollback(root);self.assertEqual((root/'active.json').read_bytes(),before)
if __name__=='__main__':unittest.main()
