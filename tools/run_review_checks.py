"""Run current source checks in the isolated review checkout."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
SAMPLE=ROOT/'samples/tongguan_v01'; REPORT=ROOT/'review-work/source'
GODOT=os.environ.get('GODOT_BIN',r'H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe')
def run(name,base,script=None,marker=None,extra=()):
    target=REPORT/name;target.mkdir(parents=True,exist_ok=True)
    cmd=[GODOT,'--headless','--path',str(base)]
    cmd+=['--script','res://'+script,'--','--report='+str(target/'details.json')] if script else ['--editor','--quit']
    cmd+=list(extra);env=os.environ.copy();env['TONGGUAN_R5_FIXTURES']=str(SAMPLE/'fixtures')
    t=time.monotonic()
    p=subprocess.run(cmd,capture_output=True,timeout=150,env=env)
    raw=p.stdout+p.stderr; (target/'runtime.txt').write_bytes(raw)
    text=raw.decode('utf-8',errors='replace')
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    ok=p.returncode==0 and not diagnostics and (marker is None or marker in text)
    result=dict(name=name,passed=ok,exit_code=p.returncode,seconds=round(time.monotonic()-t,3),diagnostics=diagnostics)
    (target/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(name,ok,p.returncode,flush=True)
    return result
def main():
    REPORT.mkdir(parents=True,exist_ok=True);results=[]
    for name,base in [('plugin',ROOT/'plugin-source'),('runtime',SAMPLE/'runtime'),('authoring',SAMPLE/'authoring')]:
        results.append(run(name+'_import',base))
    rows=[
      ('old_document',ROOT/'plugin-source','tests/test_document.gd','DOCUMENT_AND_ROUTE: PASS'),
      ('art_import',ROOT/'plugin-source','tests/test_art_import_feedback.gd','"failures":[]'),
      ('size_guard',SAMPLE/'authoring','tests/test_r3_size_guard.gd','R3_SIZE_GUARD: PASS'),
      ('geometry',SAMPLE/'authoring','tests/test_review_geometry.gd','"failures":[]'),
      ('ownership',SAMPLE/'runtime','tests/test_review_ownership.gd','"failures":[]'),
      ('publication',SAMPLE/'runtime','tests/test_final_publication.gd','"failures":[]'),
      ('view',SAMPLE/'runtime','tests/test_r4_view.gd','"failures":[]'),
      ('passage',SAMPLE/'runtime','tests/test_r3_passage.gd','"failures":[]'),
      ('construction',SAMPLE/'runtime','tests/test_construction.gd','"failures":[]'),
      ('save_migration',SAMPLE/'runtime','tests/test_r5_saves.gd','"failures":[]'),
      ('original_host',SAMPLE/'runtime','tests/test_original_host.gd','"failures":[]'),
      ('manual_layout',SAMPLE/'authoring','tests/test_final_layout.gd','"failures":[]'),
      ('authoring',SAMPLE/'authoring','tests/test_r3_authoring.gd','"failures":[]')]
    for row in rows:
        try:results.append(run(*row))
        except Exception as e:results.append(dict(name=row[0],passed=False,error=str(e)));print(row[0],str(e),flush=True)
    p=subprocess.run(['python',str(ROOT/'plugin-source/verify_source.py')],capture_output=True)
    (REPORT/'plugin_static.txt').write_bytes(p.stdout+p.stderr);results.append(dict(name='plugin_static',passed=p.returncode==0))
    value=dict(passed=all(r['passed'] for r in results),tests=results)
    (REPORT/'summary.json').write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    return value['passed']
if __name__=='__main__':raise SystemExit(0 if main() else 1)
