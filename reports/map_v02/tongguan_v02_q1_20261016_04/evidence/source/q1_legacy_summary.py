"""Keep failed attempts, while binding required legacy gates to their actual baseline."""
from common import ROOT,read,save,sha
from pathlib import Path
from PIL import Image
import re

def main():
    base=ROOT/'review-work/map_v02';old=read(base/'q1_regressions_02/summary.json');e2e=base/'q1_regression_native_e2e';release=base/'q1_old_release_pixel_control'
    tests=[r for r in old['tests'] if r['case']!='runtime_native']
    fixed=read(e2e/'runtime_retry_02_result.json');execution=read(e2e/'runtime_retry_02_run.json')
    tests.append(dict(case='runtime_native_e2e_with_isolated_publication',passed=execution['exit_code']==0 and not fixed['failures'],checks=fixed['checks'],evidence=str(e2e/'runtime_retry_02_result.json')))
    pixels=read(release/'result.json');run=read(release/'run.json');size=Image.open(release/'01_manual_layout_and_locked_tree.png').size
    tests.append(dict(case='frozen_authoring_release_50_pixel_cycles',passed=run['exit_code']==0 and not pixels['failures'] and pixels['cycles']==50,checks=pixels['checks'],actual_authoring_image_size=list(size),evidence=str(release/'result.json')))
    binding=read(e2e/'protected_source_bindings.json')
    bad=[r['source'] for r in binding['files'] if sha(r['source'])!=r['sha256'] or sha(r['copy'])!=r['sha256']]
    debug=read(e2e/'final_authoring_50_pixel_cycles_result.json')
    scaled=base/'q1_scaled_authoring_control';rca=read(scaled/'RCA.json');corrected=read(scaled/'result.json')
    tests.append(dict(case='source_authoring_50_pixel_cycles_correct_coordinate_mapping',passed=rca['passed'] and not corrected['failures'] and corrected['cycles']==50 and rca['corrected_png_unique_hashes']==1,checks=corrected['checks'],evidence=str(scaled/'RCA.json'),pixel_threshold='exact; unchanged'))
    value=dict(passed=all(t['passed'] for t in tests) and not bad,tests=tests,protected_source_bindings_passed=not bad,source_binding_mismatches=bad,failed_attempts_retained=[str(base/'q1_regressions/geometry.txt'),str(base/'q1_regressions_02/runtime_native_result.json'),str(e2e/'runtime_native_retry_result.json'),str(e2e/'final_authoring_50_pixel_cycles_result.json')],required_authoring_pixel_configuration='unchanged official Windows release, original configured window; not labelled as a 1080p runtime benchmark',extra_debug_fullscreen=dict(passed=not debug['failures'],checks=debug['checks'],failures=debug['failures'],actual_image_size=list(Image.open(e2e/'01_manual_layout_and_locked_tree.png').size),status='retained diagnostic failure; never counted as a pass',scope='source/debug authoring at forced fullscreen; original protected data and stock release control pass'),notes=['Legacy test directories and native GUI execution were made explicit without editing test code.','Native authoring/runtime exchange uses an explicit copied publication in an isolated APPDATA directory.','Three Q1-only observer files changed during early old-code validation; all pre-Q1 protected target code is source-identical and the final Q1 observer is separately frozen.'])
    value['extra_debug_fullscreen']['status']='resolved measurement coordinate error; original failure retained'
    value['extra_debug_fullscreen']['resolution']=str(scaled/'RCA.json')
    value['extra_debug_fullscreen']['cause']='1440x900 logical coordinates used on a 1728x1080 texture; same logical ROI mapped through actual 1.2 stretch now has identical pixels across all 50 cycles'
    value['notes'].append('Only the new diagnostic overrides ROI coordinate mapping; original authoring code and exact pixel equality threshold are unchanged.')
    save(base/'Q1_LEGACY_PROTECTION_SUMMARY.json',value);print('Q1_LEGACY_GATES',value['passed'],'suites',len(tests),'corrected_source_pixel_passed',rca['passed'])
    return 0 if value['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
