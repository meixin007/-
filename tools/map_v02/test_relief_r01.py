"""Independent analytic checks for height-driven terrain, not beauty assertions."""
import unittest
import numpy as np
try:
    from relief_r01_prepare import analyze,render,bilinear
except ImportError:
    analyze=render=bilinear=None

class TerrainContract(unittest.TestCase):
    def setUp(self):self.assertIsNotNone(analyze,'height-driven relief implementation required')
    def test_flat_has_no_fabricated_landforms(self):
        a=analyze(np.full((80,100),400,dtype=np.float32),40)
        self.assertLess(float(abs(a['tpi']).max()),.001)
        self.assertLess(float(a['slope'].max()),.001)
    def test_slope_aspect_controls_lighting(self):
        x=np.arange(100,dtype=np.float32)[None,:]*40
        east=np.repeat(400+x*.3,80,axis=0);west=np.repeat(400-x*.3,80,axis=0)
        a=analyze(east,40);b=analyze(west,40)
        self.assertGreater(float(a['light'][20:60,20:80].mean()),float(b['light'][20:60,20:80].mean()))
    def test_ridge_valley_sign(self):
        x=(np.arange(101)-50)*40.0
        hump=np.exp(-(x/220)**2)*80
        a=analyze(np.repeat((400+hump)[None,:],81,axis=0),40)
        b=analyze(np.repeat((400-hump)[None,:],81,axis=0),40)
        self.assertGreater(float(a['tpi'][40,50]),0)
        self.assertLess(float(b['tpi'][40,50]),0)
    def test_world_sample_is_independent_of_tile(self):
        field=np.arange(80*100,dtype=np.float32).reshape(80,100)
        self.assertEqual(float(bilinear(field,np.array([23.5]),np.array([31.5]),[0,0],1)[0]),float(field[31,23]))
    def test_invalid_numeric_source_rejected(self):
        h=np.ones((10,10));h[3,4]=np.nan
        with self.assertRaises(ValueError):analyze(h,40)
    def test_outer_sampling_clamps_coordinates(self):
        field=np.array([[1,2],[3,4]],dtype=np.float32)
        actual=bilinear(field,np.array([-100,100]),np.array([-100,100]),[0,0],1)
        np.testing.assert_array_equal(actual,[1,4])

if __name__=='__main__':unittest.main()
