"""Verify the real E1 Windows PCK from a clean directory, without source caches."""
import argparse,re,subprocess,time
from common import ROOT,read,save,sha


def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);p.add_argument('--run-id',required=True);a=p.parse_args()
    if not all(re.fullmatch('[A-Za-z0-9_-]+',v) for v in [a.build_id,a.run_id]):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;clean=work/'CLEAN_WINDOWS';target=work/a.run_id;target.mkdir(parents=True,exist_ok=False)
    if (clean/'.godot').exists() or (clean/'project.godot').exists():raise RuntimeError('not a clean runtime directory')
    command=[str(clean/'TongguanE1.exe'),'--fullscreen','--log-file',str(target/'runtime.log'),'--','--e1-native-check','--report='+str(target/'result.json')]
    started=time.monotonic()
    try:
        result=subprocess.run(command,cwd=clean,capture_output=True,timeout=150)
        raw=result.stdout+result.stderr;exit_code=result.returncode
    except subprocess.TimeoutExpired as error:
        raw=(error.stdout or b'')+(error.stderr or b'');exit_code=None
    (target/'console.txt').write_bytes(raw)
    text=(target/'runtime.log').read_text(encoding='utf-8',errors='replace') if (target/'runtime.log').exists() else raw.decode('utf-8',errors='replace')
    (target/'runtime.txt').write_text(text,encoding='utf-8')
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    value=read(target/'result.json') if (target/'result.json').exists() else dict(failures=['missing result'])
    passed=exit_code==0 and not diagnostics and not value.get('failures')
    value.update(technical_passed=passed,command=command,cwd=str(clean),exit_code=exit_code,diagnostics=diagnostics,seconds=time.monotonic()-started,
        no_source_project_or_editor_cache=True,artifacts={p.name:sha(p) for p in clean.iterdir() if p.suffix in {'.exe','.pck'}})
    save(target/'result.json',value)
    print('E1_NATIVE',passed,'checks',value.get('checks'),'failures',value.get('failures'),'diagnostics',diagnostics,flush=True)
    return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
