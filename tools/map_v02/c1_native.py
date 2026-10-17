"""Run the clean exported C1 binary in an actual FHD native window."""
import argparse,re,subprocess,time
import numpy as np
from PIL import Image
from common import ROOT,read,save,sha

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);p.add_argument('--run-id',required=True);a=p.parse_args()
    if not all(re.fullmatch('[A-Za-z0-9_-]+',s) for s in [a.build_id,a.run_id]):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;clean=work/'CLEAN_WINDOWS';out=work/a.run_id;out.mkdir(exist_ok=False)
    command=[str(clean/'TongguanC1.exe'),'--fullscreen','--log-file',str(out/'runtime.log'),'--','--c1-check','--report='+str(out/'result.json')]
    start=time.monotonic()
    try:
        proc=subprocess.run(command,cwd=clean,capture_output=True,timeout=250);raw=proc.stdout+proc.stderr;code=proc.returncode
    except subprocess.TimeoutExpired as e:raw=(e.stdout or b'')+(e.stderr or b'');code=None
    (out/'console.txt').write_bytes(raw)
    log=out/'runtime.log';text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else raw.decode('utf-8',errors='replace')
    (out/'runtime.txt').write_text(text,encoding='utf-8')
    diag=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    result=read(out/'result.json') if (out/'result.json').exists() else dict(failures=['missing result'])
    comparisons=[]
    for row in result.get('gpu_comparisons',[]):
        x,y,w,h=row['roi'];one=np.asarray(Image.open(out/row['a']).convert('RGB'))[y:y+h,x:x+w].astype(np.int16);two=np.asarray(Image.open(out/row['b']).convert('RGB'))[y:y+h,x:x+w].astype(np.int16)
        delta=np.abs(one-two);maximum=int(delta.max());ok=(maximum<=row['frozen_max_channel_delta'])==row['expect_equal']
        comparisons.append(dict(**row,passed=ok,max_channel_delta=maximum,differing_pixels=int(np.any(delta>0,axis=2).sum())))
        if not ok:result.setdefault('failures',[]).append('GPU comparison '+row['case'])
    result['gpu_comparisons']=comparisons
    passed=code==0 and not diag and not result.get('failures')
    result.update(technical_passed=passed,command=command,exit_code=code,diagnostics=diag,seconds=time.monotonic()-start,artifacts={p.name:sha(p) for p in clean.iterdir() if p.suffix in {'.exe','.pck'}})
    save(out/'result.json',result)
    print('C1_NATIVE',passed,'checks',result.get('checks'),'failures',result.get('failures'),'diagnostics',diag[:12],flush=True)
    return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
