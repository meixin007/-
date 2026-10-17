"""C1-owned compatibility evidence, always with explicit exit guards and fixtures."""
import os,re,subprocess
from common import ROOT,RUNTIME,read,save
from v1_build import GODOT

def main():
    out=ROOT/'review-work/map_v02/c1_regressions';out.mkdir(exist_ok=False)
    cases=[('policy',RUNTIME,'res://tests/v02/c1_policy_runner.gd'),('v2_core',RUNTIME,'res://tests/v02/test_v2_presentation.gd'),('e3_core',RUNTIME,'res://tests/v02/test_e3_lifecycle.gd'),('e2_core',RUNTIME,'res://tests/v02/test_e2_query.gd'),('e1_adapter',RUNTIME,'res://tests/v02/test_e1_package.gd'),('geometry',ROOT/'samples/tongguan_v01/authoring','res://tests/test_review_geometry.gd'),('ownership',RUNTIME,'res://tests/test_review_ownership.gd'),('publication',RUNTIME,'res://tests/test_final_publication.gd'),('passage',RUNTIME,'res://tests/test_r3_passage.gd'),('construction',RUNTIME,'res://tests/test_construction.gd'),('saves',RUNTIME,'res://tests/test_r5_saves.gd')]
    results=[];env=os.environ.copy();env['TONGGUAN_R5_FIXTURES']=str(ROOT/'samples/tongguan_v01/fixtures')
    for name,folder,script in cases:
        report=out/(name+'_result.json');cmd=[GODOT,'--headless','--path',str(folder),'--script',script,'--','--report='+str(report)]
        p=subprocess.run(cmd,capture_output=True,timeout=100,env=env);text=(p.stdout+p.stderr).decode('utf-8',errors='replace');(out/(name+'.txt')).write_text(text,encoding='utf-8')
        diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
        value=read(report) if report.is_file() else (dict(failures=[]) if name=='policy' and p.returncode==0 else dict(failures=['missing result']))
        passed=p.returncode==0 and not diagnostics and not value.get('failures') and value.get('passed',True)
        results.append(dict(name=name,command=cmd,fixture_environment=env['TONGGUAN_R5_FIXTURES'],exit_code=p.returncode,diagnostics=diagnostics,passed=passed));print('C1_REGRESSION',name,passed,flush=True)
    save(out/'summary.json',dict(passed=all(r['passed'] for r in results),tests=results))
    return 0 if all(r['passed'] for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
