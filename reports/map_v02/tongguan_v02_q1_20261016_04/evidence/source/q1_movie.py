"""Supplemental unedited native fixture recording; excluded from performance statistics."""
import re,subprocess
from common import ROOT,read,save,sha

def main():
    work=ROOT/'review-work/map_v02/tongguan_v02_q1_20261016_04';out=work/'fixture_movie';out.mkdir(exist_ok=False)
    exe=work/'CLEAN_WINDOWS/TongguanQ1.exe'
    command=[str(exe),'--fullscreen','--write-movie',str(out/'fixtures.avi'),'--fixed-fps','30','--log-file',str(out/'runtime.log'),'--','--q1=fixtures','--report='+str(out/'engine_result.json')]
    p=subprocess.run(command,cwd=exe.parent,capture_output=True,timeout=360)
    raw=(p.stdout+p.stderr).decode('utf-8',errors='replace');(out/'console.txt').write_text(raw,encoding='utf-8')
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',raw,re.M)
    data=read(out/'engine_result.json') if (out/'engine_result.json').exists() else dict(failures=['missing result'])
    movie=out/'fixtures.avi';passed=p.returncode==0 and not diagnostics and not data.get('failures') and movie.is_file() and movie.stat().st_size>100000
    save(out/'result.json',dict(passed=passed,exit_code=p.returncode,command=command,diagnostics=diagnostics,checks=data.get('checks'),failures=data.get('failures'),movie_sha256=sha(movie) if movie.exists() else None,movie_bytes=movie.stat().st_size if movie.exists() else None,actual_viewport=data.get('actual_viewport'),artifacts={f.name:sha(f) for f in exe.parent.glob('*') if f.suffix in {'.exe','.pck'}},scope='Unedited Godot native MovieWriter at fixed 30 fps: supplementary visual trajectory evidence only. Formal real-time frame measurements are separate, uncapped, and contain no capture readback.'))
    print('Q1_FIXTURE_MOVIE',passed,'checks',data.get('checks'), 'diagnostics',diagnostics[:3],flush=True)
    return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
