"""Execute the current regression fixtures against a pristine read-only baseline copy."""
from pathlib import Path
import json,os,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'review-work/red-baseline'
GODOT=r'H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe'
BASE='26a45be93e62fc56199ed42d98895926380383c5'
def main():
    if WORK.exists():raise RuntimeError('Fresh red tree required')
    WORK.mkdir(parents=True)
    archive=WORK/'baseline.zip';subprocess.run(['git','archive','--format=zip','-o',str(archive),BASE],cwd=ROOT,check=True)
    with zipfile.ZipFile(archive) as z:z.extractall(WORK/'tree')
    paths=['authoring/tests/test_review_geometry.gd','runtime/tests/test_review_ownership.gd','runtime/tests/test_review_edges.gd','runtime/review/tree_edge_acceptance.gd']
    for rel in paths:
        src=ROOT/'samples/tongguan_v01'/rel;dst=WORK/'tree/samples/tongguan_v01'/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    rows=[]
    for component,test,headless in [('authoring','test_review_geometry',True),('runtime','test_review_ownership',True),('runtime','test_review_edges',False)]:
        base=WORK/'tree/samples/tongguan_v01'/component;target=WORK/test;target.mkdir()
        p=subprocess.run([GODOT,'--headless','--path',str(base),'--editor','--quit'],capture_output=True,timeout=120)
        (target/'import.txt').write_bytes(p.stdout+p.stderr)
        cmd=[GODOT,*(['--headless'] if headless else []),'--path',str(base),'--script','res://tests/'+test+'.gd','--','--report='+str(target/'details.json')]
        p=subprocess.run(cmd,capture_output=True,timeout=180);(target/'runtime.txt').write_bytes(p.stdout+p.stderr)
        result=json.loads((target/'details.json').read_text(encoding='utf-8'))
        row=dict(name=test,exit_code=p.returncode,checks=result['checks'],failures=result['failures'],exposes_regression=p.returncode==1 and bool(result['failures']))
        rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
    (WORK/'summary.json').write_text(json.dumps(dict(baseline=BASE,tests=rows),indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    return all(r['exposes_regression'] for r in rows)
if __name__=='__main__':raise SystemExit(0 if main() else 1)
