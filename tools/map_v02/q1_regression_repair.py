"""Reconnect the legacy native authoring/runtime fixture exchange in isolated dirs."""
import os,re,shutil,subprocess
from pathlib import Path
from common import ROOT,read,save,source_files,sha
from v1_build import GODOT,execute

def main():
    prior=ROOT/'review-work/map_v02/q1_regressions_02';out=ROOT/'review-work/map_v02/q1_regression_native_e2e';out.mkdir(exist_ok=False)
    protected={str((ROOT/r['path']).resolve()) for r in read(ROOT/'review-work/map_v02/q1_boundary/before.json')['files']}
    bindings=read(prior/'bindings.json');old_rows=[r for r in bindings['files'] if str(Path(r['source']).resolve()) in protected]
    bad=[r for r in old_rows if sha(r['source'])!=r['sha256'] or sha(r['copy'])!=r['sha256']]
    if bad:raise RuntimeError('protected source mismatch')
    save(out/'protected_source_bindings.json',dict(passed=True,files=old_rows,unrelated_q1_instrumentation_drift=bindings['mismatches'],scope='only pre-Q1 protected code is the old regression target; final Q1 instrumentation is tested in the separately frozen release'))
    stages={}
    for key in ['runtime','authoring']:
        source=prior/key;target=out/key;target.mkdir();stages[key]=target
        for file in source_files(source):
            dest=target/file.relative_to(source);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(file,dest)
        user_name='tongguan_q1_native_e2e_'+key;project=target/'project.godot';project.write_text(re.sub(r'config/custom_user_dir_name="[^"]+"','config/custom_user_dir_name="'+user_name+'"',project.read_text(encoding='utf-8')),encoding='utf-8')
        (Path(os.environ['APPDATA'])/user_name/'tests').mkdir(parents=True,exist_ok=True);execute(out,target,'import_'+key,['--editor','--quit'])
    env=os.environ.copy();env['APPDATA']=str(out/'isolated_exchange');env['TONGGUAN_R5_FIXTURES']=str(ROOT/'samples/tongguan_v01/fixtures');results=[]
    def native(name,key,script=None):
        path=out/(name+'_result.json');command=[GODOT,'--fullscreen','--path',str(stages[key]),*(['--script',script] if script else []),'--',*(['--acceptance'] if script is None else []),'--report='+str(path)]
        process=subprocess.run(command,capture_output=True,timeout=180,env=env);text=(process.stdout+process.stderr).decode('utf-8',errors='replace');(out/(name+'.txt')).write_text(text,encoding='utf-8');diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
        value=read(path) if path.exists() else dict(failures=['missing report']);okay=process.returncode==0 and not diagnostics and not value.get('failures')
        row=dict(case=name,passed=okay,command=command,exit_code=process.returncode,diagnostics=diagnostics,checks=value.get('checks'));results.append(row);print('Q1_NATIVE_REGRESSION',name,okay,flush=True)
        return value
    published=native('authoring_native_exchange','authoring','res://tests/test_r3_authoring_scene.gd')
    source=Path(published['publication_path']);dest=Path(os.environ['APPDATA'])/'tongguan_q1_native_e2e_runtime/authoring/tests_native_publication.json';dest.parent.mkdir(parents=True,exist_ok=True)
    if dest.exists():raise RuntimeError('fresh fixture destination required')
    shutil.copyfile(source,dest);save(out/'exchange.json',dict(actual_native_publication=str(source),copied_to=str(dest),sha256=sha(source),copied_sha256=sha(dest),prior_test_failure='runtime user directory had no native authoring publication after isolation',test_code_changed=False))
    native('runtime_native_retry','runtime','res://tests/test_r3_scene.gd')
    native('final_authoring_50_pixel_cycles','authoring')
    old=read(prior/'summary.json')['tests'];passed_old=[r for r in old if r['case']!='runtime_native']
    save(out/'summary.json',dict(passed=all(r['passed'] for r in passed_old+results),protected_source_bindings_passed=True,tests=passed_old+results,superseded_failed_case='q1_regressions_02/runtime_native',source_and_fixture_failures_retained=True,isolated_native_exchange=True));return 0 if all(r['passed'] for r in passed_old+results) else 1
if __name__=='__main__':raise SystemExit(main())
