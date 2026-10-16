"""Verify sealed baseline source/artifacts and unchanged source identity data."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1];BASE='26a45be93e62fc56199ed42d98895926380383c5'
SEALED=Path(r'H:\tongguan_slice_v01_20261014\p10_final\releases\tongguan_v01_final_20261015_03')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    errors=[];source_count=0;assets=[]
    for row in read(SEALED/'SOURCE_MANIFEST.json')['files']:
        p=SEALED/('SOURCE_'+row['component'].upper())/row['path'];source_count+=1
        if not p.is_file() or sha(p)!=row['sha256']:errors.append('sealed source:'+row['path'])
    expected={'TongguanFinal.exe':'6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20',
      'TongguanAuthoring.exe':'6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20',
      'TongguanFinal.pck':'16de08788dcb662ce82c4a6abe964b2ed95ec249100cd3ccede7b0a99f4fc072',
      'TongguanAuthoring.pck':'4b458cf6437e4db7106971d5f4a86ea963eb1be1d2c69849c049842a0fc2b500'}
    for name,h in expected.items():
        if sha(SEALED/'Windows'/name)!=h:errors.append('sealed Windows:'+name)
    original_zip=SEALED.parents[2]/'deliveries/tongguan_v01_final_20261015_03.zip'
    # The original delivery lives under the isolated project root.
    original_zip=Path(r'H:\tongguan_slice_v01_20261014\deliveries\tongguan_v01_final_20261015_03.zip')
    if sha(original_zip)!='daace306044b00077a81cdbd4b63a36dadb8f3721011c214ec5becf68c85c6d8':errors.append('sealed zip')
    names=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT).decode('utf-8').splitlines()
    selected=[n for n in names if n.startswith('plugin-source/') or '/bundle/' in n or '/final/fixtures/' in n or '/original-build/' in n or n.startswith('docs/')]
    for n in selected:
        old=subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT)
        if not (ROOT/n).is_file() or hashlib.sha256(old).hexdigest()!=sha(ROOT/n):errors.append('protected baseline data:'+n)
        if n.endswith('.png'):assets.append(dict(path=n,sha256=sha(ROOT/n)))
    previous=Path(r'H:\tongguan_github_20261015\repository')
    previous_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=previous).decode().strip()
    clean=not subprocess.check_output(['git','status','--porcelain'],cwd=previous).strip()
    if previous_head!=BASE or not clean:errors.append('publication baseline checkout changed')
    result=dict(passed=not errors,baseline_commit=BASE,sealed_sources_checked=source_count,sealed_windows=expected,sealed_zip_sha256=sha(original_zip),
      protected_baseline_files=len(selected),unchanged_sample_images=assets,baseline_checkout_head=previous_head,baseline_checkout_clean=clean,
      main_workspace_exact_git_state='not claimed; no initial full-state snapshot',errors=errors)
    target=ROOT/'review-work/protection.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='unchanged_sample_images'},ensure_ascii=False),flush=True)
    return result['passed']
if __name__=='__main__':raise SystemExit(0 if main() else 1)
