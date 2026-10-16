"""Package the exact measured build; refuse to overwrite a previous package."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1];BUILD='tongguan_v01_revfix_20261015_02'
REL=ROOT/'review-work/releases'/BUILD;REPORT=ROOT/'reports/review_26a45be'
DEST=ROOT/'review-work/deliveries';NAME='tongguan-v0.1-rev01-03-windows-x64-20261015.zip'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    DEST.mkdir(parents=True,exist_ok=True);output=DEST/NAME
    if output.exists():raise RuntimeError('Never overwrite an existing candidate package')
    metadata=json.loads((REL/'RELEASE.json').read_text())
    files={('Windows/'+p.name):p for p in (REL/'Windows').iterdir() if p.is_file()}
    for name in ['THIRD_PARTY_NOTICES.md','third_party/godot/LICENSE.txt','third_party/godot/COPYRIGHT.txt','third_party/godot/AUTHORS.md']:
        p=ROOT/name
        if p.exists():files[name]=p
    files['ATTRIBUTION.txt']=ROOT/'samples/tongguan_v01/runtime/bundle/ATTRIBUTION.txt'
    for p in REPORT.rglob('*'):
        if p.is_file() and p.suffix in ['.json','.md'] and 'process_samples' not in p.name:files['reports/'+p.relative_to(REPORT).as_posix()]=p
    with zipfile.ZipFile(output,'x',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,p in sorted(files.items()):z.write(p,name)
        z.writestr('Start-Final.cmd','@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0Windows\\TongguanFinal.exe"\r\n')
        z.writestr('Start-Authoring.cmd','@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0Windows\\TongguanAuthoring.exe"\r\n')
        z.writestr('README.txt',BUILD+'\r\nExtract all files. Run Start-Final.cmd or Start-Authoring.cmd.\r\nCurrent stage awaits user acceptance; original sealed release remains unchanged.\r\nEXE and same-name PCK must stay together. Saves retain the same user directory and semantics.\r\nSee reports/REPORT.md and reports/RELEASE.json.\r\n')
    with zipfile.ZipFile(output) as z:
        assert z.testzip() is None
        for name,row in metadata['artifacts'].items():assert hashlib.sha256(z.read('Windows/'+name)).hexdigest()==row['sha256']
        # Required notices for redistributing the official Godot template.
        assert any(n.endswith('LICENSE.txt') for n in z.namelist())
    value=dict(build_id=BUILD,filename=NAME,bytes=output.stat().st_size,sha256=sha(output),member_count=len(files)+3,zip_integrity_passed=True,all_four_embedded_artifact_hashes_passed=True)
    (REPORT/'DELIVERY_ARTIFACTS.json').write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    text=''.join(row['sha256']+'  '+name+'\n' for name,row in metadata['artifacts'].items())+value['sha256']+'  '+NAME+'\n'
    (DEST/'SHA256SUMS.txt').write_text(text,encoding='utf-8')
    print(json.dumps(value),flush=True)
if __name__=='__main__':main()
