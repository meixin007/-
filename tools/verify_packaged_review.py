"""Verify the packaged EXE/PCK pairs from a fresh extraction."""
from pathlib import Path
import hashlib,json,re,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1];REPORT=ROOT/'reports/review_26a45be';WORK=ROOT/'review-work'
def main():
    delivery=json.loads((REPORT/'DELIVERY_ARTIFACTS.json').read_text())
    target=WORK/'packaged-smoke'/(delivery['build_id']+'-final')
    if target.exists():raise RuntimeError('Fresh extraction required')
    target.mkdir(parents=True)
    package=WORK/'deliveries'/delivery['filename'];metadata=json.loads((REPORT/'RELEASE.json').read_text())
    with zipfile.ZipFile(package) as z:
        for name,row in metadata['artifacts'].items():
            raw=z.read('Windows/'+name);assert hashlib.sha256(raw).hexdigest()==row['sha256']
            p=target/'Windows'/name;p.parent.mkdir(exist_ok=True);p.write_bytes(raw)
        # Every relative Markdown evidence link in the bundled report resolves.
        text=z.read('reports/REPORT.md').decode('utf-8')
        for rel in re.findall(r'\]\(([^)]+)\)',text):
            if '://' not in rel:assert 'reports/'+rel in z.namelist(),rel
    rows=[]
    # Runtime has a product --probe-build entry; authoring deliberately does not.
    # Its complete native163 acceptance already ran against the same hashes.
    out=target/'TongguanFinal_confirmed.json'
    p=subprocess.run([str(target/'Windows/TongguanFinal.exe'),'--headless','--','--probe-build','--report='+str(out)],capture_output=True,timeout=30)
    value=json.loads(out.read_text())
    rows.append(dict(component='TongguanFinal',method='fresh_extracted_boot_probe',exit_code=p.returncode,build=value,passed=p.returncode==0 and value['build_id']==delivery['build_id'] and value['release']))
    author=json.loads((REPORT/'native/authoring/result.json').read_text())
    bound=all(author['artifacts'][name]==row['sha256'] for name,row in metadata['artifacts'].items())
    rows.append(dict(component='TongguanAuthoring',method='byte_identical_to_complete_native_acceptance',checks=author['checks'],build_id=author['build_id'],passed=bound and author['execution_passed'] and author['build_id']==delivery['build_id']))
    result=dict(build_id=delivery['build_id'],package_sha256=delivery['sha256'],fresh_extraction=True,relative_report_links_resolved=True,components=rows,passed=all(r['passed'] for r in rows))
    (WORK/'packaged_smoke.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result),flush=True);return result['passed']
if __name__=='__main__':raise SystemExit(0 if main() else 1)
