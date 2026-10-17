"""Run the unchanged repository validator on the exact non-ignored source payload."""
import json,shutil,subprocess,sys
from common import ROOT,read,save,sha

def main():
    work=ROOT/'review-work/map_v02/tongguan_v02_q1_20261016_04';out=work/'repository_validation';out.mkdir(exist_ok=True)
    stage=out/'source_payload';stage.mkdir(exist_ok=True)
    names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode('utf-8').split('\0')
    rows=[]
    for name in sorted(set(filter(None,names))):
        source=ROOT/name
        if not source.is_file():raise AssertionError('missing payload '+name)
        target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target);rows.append(dict(path=name,sha256=sha(source)))
    # Exact script and manifest semantics; no filtering inside the validator.
    p=subprocess.run([sys.executable,str(stage/'verify_repository.py')],cwd=stage,capture_output=True)
    raw=(p.stdout+p.stderr).decode('utf-8',errors='replace');(out/'source_payload.txt').write_text(raw,encoding='utf-8')
    result=json.loads(raw)
    save(out/'result.json',dict(passed=p.returncode==0 and result['passed'],command=[sys.executable,str(stage/'verify_repository.py')],validator_sha256=sha(ROOT/'verify_repository.py'),staged_validator_sha256=sha(stage/'verify_repository.py'),payload_count=len(rows),payload_manifest=rows,result=result,scope='Exact git ls-files --cached --others --exclude-standard payload. Ignored local release ZIPs and raw runtime logs are intentionally preserved in the original tree, not submitted as Git source. Direct original-tree failed scan retained separately.'))
    print(json.dumps(dict(passed=p.returncode==0 and result['passed'],payload_count=len(rows),result=result),ensure_ascii=False));return p.returncode
if __name__=='__main__':raise SystemExit(main())
