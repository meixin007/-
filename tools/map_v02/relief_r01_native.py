"""Native Godot captures plus independently measured paged/reference GPU comparisons."""
import argparse,re,subprocess,time
import numpy as np
from PIL import Image
from common import ROOT,read,save,sha
def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);p.add_argument('--run-id',required=True);a=p.parse_args()
    if not all(re.fullmatch('[A-Za-z0-9_-]+',s) for s in [a.build_id,a.run_id]):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;clean=work/'CLEAN_WINDOWS';out=work/a.run_id;out.mkdir(exist_ok=False)
    command=[str(clean/'TongguanReliefR1.exe'),'--fullscreen','--log-file',str(out/'runtime.log'),'--','--relief-capture','--report='+str(out/'result.json')]
    start=time.monotonic()
    try:
        process=subprocess.run(command,cwd=clean,capture_output=True,timeout=260);raw=process.stdout+process.stderr;code=process.returncode
    except subprocess.TimeoutExpired as error:raw=(error.stdout or b'')+(error.stderr or b'');code=None
    (out/'console.txt').write_bytes(raw)
    text=(out/'runtime.log').read_text(encoding='utf-8',errors='replace') if (out/'runtime.log').exists() else raw.decode('utf-8',errors='replace');(out/'runtime.txt').write_text(text,encoding='utf-8')
    diag=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    value=read(out/'result.json') if (out/'result.json').exists() else dict(failures=['missing result'])
    results=[]
    for row in value.get('comparisons',[]):
        x,y,w,h=row['roi'];one=np.asarray(Image.open(out/row['a']).convert('RGB'))[y:y+h,x:x+w].astype(np.int16);two=np.asarray(Image.open(out/row['b']).convert('RGB'))[y:y+h,x:x+w].astype(np.int16)
        delta=np.abs(one-two);maximum=int(delta.max());passed=(maximum<=row['frozen_max_channel_delta'])==row['expect_equal']
        results.append(dict(**row,passed=passed,max_channel_delta=maximum,differing_pixels=int(np.any(delta>0,axis=2).sum()),pixels=w*h))
    if not all(r['passed'] for r in results):value.setdefault('failures',[]).extend(['GPU comparison '+r['case'] for r in results if not r['passed']])
    passed=code==0 and not diag and not value.get('failures')
    value.update(technical_passed=passed,command=command,exit_code=code,diagnostics=diag,seconds=time.monotonic()-start,gpu_comparisons=results,artifacts={p.name:sha(p) for p in clean.iterdir() if p.suffix in {'.exe','.pck'}});save(out/'result.json',value)
    print('RELIEF_NATIVE',passed,'script_checks',value.get('checks'),'gpu_comparisons',len(results),'failures',value.get('failures'),'diagnostics',diag[:8],flush=True)
    return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
