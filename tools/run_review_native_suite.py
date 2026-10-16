"""Native Release tests are serial; display-load budgets are a separate result."""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
    results=[]
    for mode in ['authoring','verify','tree_edges','cycles','performance','soak','load']:
        p=subprocess.run([sys.executable,str(ROOT/'tools/run_review_native.py'),'--mode',mode],cwd=ROOT)
        result=ROOT/'review-work/native/release'/mode/'result.json'
        value=json.loads(result.read_text(encoding='utf-8')) if result.exists() else {}
        results.append(dict(mode=mode,exit_code=p.returncode,execution_passed=value.get('execution_passed',False),budget_passed=value.get('budget_passed',False)))
    overall=dict(tests=results,technical_passed=all(r['execution_passed'] for r in results),all_budgets_passed=all(r['budget_passed'] for r in results))
    (ROOT/'review-work/native/summary.json').write_text(json.dumps(overall,indent=2)+'\n',encoding='utf-8')
    return overall['technical_passed']
if __name__=='__main__':raise SystemExit(0 if main() else 1)
