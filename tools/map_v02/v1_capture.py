"""Run one native V1 review capture; does not touch default saves or old releases."""
from pathlib import Path
import argparse,subprocess,time,re
from common import ROOT,read,save,sha
def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);p.add_argument('--run-id',required=True);a=p.parse_args()
    work=ROOT/'review-work/map_v02'/a.build_id
    target=work/a.run_id;target.mkdir(parents=True,exist_ok=False)
    exe=work/'Windows/TongguanV1.exe'
    cmd=[str(exe),'--fullscreen','--log-file',str(target/'runtime.log'),'--','--v1-capture','--report='+str(target/'result.json')]
    started=time.monotonic()
    try:
        result=subprocess.run(cmd,cwd=exe.parent,capture_output=True,timeout=150)
        raw=result.stdout+result.stderr;exit_code=result.returncode
    except subprocess.TimeoutExpired as error:
        raw=(error.stdout or b'')+(error.stderr or b'');exit_code=None
    (target/'console.txt').write_bytes(raw)
    log=target/'runtime.log';text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else raw.decode('utf-8',errors='replace')
    (target/'runtime.txt').write_text(text,encoding='utf-8')
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    value=read(target/'result.json') if (target/'result.json').exists() else {'failures':['missing result']}
    passed=exit_code==0 and not diagnostics and not value.get('failures')
    value.update(command=cmd,exit_code=exit_code,diagnostics=diagnostics,seconds=time.monotonic()-started,technical_passed=passed,
                 artifacts={path.name:sha(path) for path in exe.parent.iterdir() if path.suffix in {'.exe','.pck'}})
    save(target/'result.json',value)
    print('V1_NATIVE',passed,'checks',value.get('checks'),'failures',value.get('failures'),'diagnostics',diagnostics,flush=True)
    return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
