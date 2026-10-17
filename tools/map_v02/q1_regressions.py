"""Old protection cases run from source-identical copies with isolated user dirs."""
import os,re,shutil,subprocess,argparse
from pathlib import Path
from common import ROOT,RUNTIME,read,save,source_files,sha
from v1_build import GODOT,execute

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--run-id',default='q1_regressions_02');args=parser.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',args.run_id):raise ValueError('run id')
    out=ROOT/'review-work/map_v02'/args.run_id;out.mkdir(parents=True,exist_ok=False)
    copies={};bindings=[]
    for key,source in [('runtime',RUNTIME),('authoring',ROOT/'samples/tongguan_v01/authoring')]:
        target=out/key;target.mkdir();copies[key]=target
        for path in source_files(source):
            dest=target/path.relative_to(source);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,dest)
            if path.name!='project.godot':bindings.append(dict(source=str(path),copy=str(dest),sha256=sha(path)))
        user_dir='tongguan_'+args.run_id+'_'+key
        for sub in ['tests','r3_tests','r5_tests']:(Path(os.environ['APPDATA'])/user_dir/sub).mkdir(parents=True,exist_ok=True)
        project=target/'project.godot';text=project.read_text(encoding='utf-8');text=re.sub(r'config/custom_user_dir_name="[^"]+"','config/custom_user_dir_name="'+user_dir+'"',text)
        project.write_text(text,encoding='utf-8');execute(out,target,'import_'+key,['--editor','--quit'])
    cases=[('c1_policy','runtime','res://tests/v02/c1_policy_runner.gd',False),('v2_core','runtime','res://tests/v02/test_v2_presentation.gd',False),('e3_core','runtime','res://tests/v02/test_e3_lifecycle.gd',False),('e2_core','runtime','res://tests/v02/test_e2_query.gd',False),('e1_adapter','runtime','res://tests/v02/test_e1_package.gd',False),('geometry','authoring','res://tests/test_review_geometry.gd',False),('tree_edges','runtime','res://tests/test_review_edges.gd',False),('ownership','runtime','res://tests/test_review_ownership.gd',False),('publication','runtime','res://tests/test_final_publication.gd',False),('passage','runtime','res://tests/test_r3_passage.gd',False),('construction','runtime','res://tests/test_construction.gd',False),('saves','runtime','res://tests/test_r5_saves.gd',False),('authoring_50_rounds','authoring','res://tests/test_r3_authoring.gd',False),('layout_pins','authoring','res://tests/test_final_layout.gd',False),('size_guard','authoring','res://tests/test_r3_size_guard.gd',False),('authoring_native','authoring','res://tests/test_r3_authoring_scene.gd',True),('runtime_native','runtime','res://tests/test_r3_scene.gd',True)]
    env=os.environ.copy();env['TONGGUAN_R5_FIXTURES']=str(ROOT/'samples/tongguan_v01/fixtures');results=[]
    for name,key,script,native in cases:
        if name=='tree_edges':native=True
        report=out/(name+'_result.json');cmd=[GODOT,*(['--fullscreen'] if native else ['--headless']),'--path',str(copies[key]),'--script',script,'--','--report='+str(report)]
        p=subprocess.run(cmd,capture_output=True,timeout=180,env=env);raw=(p.stdout+p.stderr).decode('utf-8',errors='replace');(out/(name+'.txt')).write_text(raw,encoding='utf-8')
        diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',raw,re.M)
        data=read(report) if report.exists() else dict(failures=[] if name in ['c1_policy','size_guard'] and p.returncode==0 else ['missing report'])
        okay=p.returncode==0 and not diagnostics and not data.get('failures') and data.get('passed',True)
        results.append(dict(case=name,passed=okay,command=cmd,exit_code=p.returncode,diagnostics=diagnostics,report=str(report) if report.exists() else None,checks=data.get('checks')));print('Q1_REGRESSION',name,okay,flush=True)
    changed=[r for r in bindings if sha(r['source'])!=r['sha256'] or sha(r['copy'])!=r['sha256']]
    save(out/'bindings.json',dict(files=bindings,mismatches=changed));save(out/'summary.json',dict(passed=all(r['passed'] for r in results) and not changed,tests=results,isolated_user_dirs=True,source_copy_mismatches=len(changed)))
    return 0 if all(r['passed'] for r in results) and not changed else 1
if __name__=='__main__':raise SystemExit(main())
