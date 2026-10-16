"""Produce a new, non-overwriting Windows Release from this review checkout."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1];SAMPLE=ROOT/'samples/tongguan_v01'
BUILD='tongguan_v01_revfix_20261015_02';WORLD='tongguan_final_validation_v1'
GODOT=os.environ.get('GODOT_BIN',r'H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe')
TEMPLATE=os.environ.get('GODOT_WINDOWS_TEMPLATE',r'H:\godot4.61\export_templates_extract\templates\windows_release_x86_64.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sources(base):
    return sorted(p for p in base.rglob('*') if p.is_file() and not any(x in ['.godot','releases','__pycache__'] for x in p.relative_to(base).parts) and p.suffix not in ['.uid','.import'] and p.name not in ['build_manifest.json','integration_result.json'])
def command(base,dest,name,args):
    p=subprocess.run([GODOT,'--headless','--path',str(base),*args],capture_output=True,timeout=180)
    raw=p.stdout+p.stderr;(dest/(name+'.txt')).write_bytes(raw)
    if p.returncode or b'SCRIPT ERROR:' in raw or b'ERROR:' in raw:raise RuntimeError(str(dest/(name+'.txt')))
def main():
    dest=ROOT/'review-work/releases'/BUILD
    if dest.exists():raise RuntimeError('Refuse to overwrite an existing release: '+str(dest))
    (dest/'Windows').mkdir(parents=True);records=[]
    for component,name in [('runtime','TongguanFinal'),('authoring','TongguanAuthoring')]:
        base=SAMPLE/component
        # Preserve source asset identity, update only code hash metadata.
        ap=base/'final/asset_manifest.json';assets=read(ap)
        assets['code_native_placeholders']['content_hashes']={p.relative_to(base).as_posix():sha(p) for p in [base/'runtime/city_canvas.gd',base/'review/canvas.gd'] if p.exists()}
        save(ap,assets)
        command(base,dest,component+'_import',['--editor','--quit'])
        for p in (base/'bundle').rglob('*.png.import'):
            p.write_text(p.read_text(encoding='utf-8').replace('mipmaps/generate=false','mipmaps/generate=true'),encoding='utf-8')
        cfg=base/'export_presets.cfg';original=cfg.read_bytes()
        metadata=read(base/'final/build_manifest.json')
        metadata.update(build_id=BUILD,baseline_commit='26a45be93e62fc56199ed42d98895926380383c5',asset_bundle_hash=sha(ap))
        metadata['files']=[dict(path=p.relative_to(base).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in sources(base)]
        save(base/'final/build_manifest.json',metadata)
        try:
            text=original.decode('utf-8').replace('custom_template/release=""','custom_template/release='+json.dumps(Path(TEMPLATE).as_posix()))
            cfg.write_text(text,encoding='utf-8')
            command(base,dest,component+'_export',['--export-release','R5 Final',str(dest/'Windows'/(name+'.exe'))])
        finally:cfg.write_bytes(original)
        for p in sources(base)+[base/'final/build_manifest.json']:
            target=dest/('SOURCE_'+component.upper())/p.relative_to(base);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
            records.append(dict(component=component,path=p.relative_to(base).as_posix(),sha256=sha(target),bytes=target.stat().st_size))
    save(dest/'SOURCE_MANIFEST.json',dict(build_id=BUILD,baseline_commit=metadata['baseline_commit'],files=records))
    artifacts={p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in sorted((dest/'Windows').iterdir())}
    save(dest/'RELEASE.json',dict(build_id=BUILD,world_id=WORLD,baseline_commit=metadata['baseline_commit'],artifacts=artifacts,source_manifest_sha256=sha(dest/'SOURCE_MANIFEST.json'),user_acceptance='pending'))
    rows=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for component in ['runtime','authoring'] for p in sources(SAMPLE/component)+[SAMPLE/component/'final/build_manifest.json']]
    save(SAMPLE/'REVIEW_SOURCE_MANIFEST.json',dict(build_id=BUILD,baseline_commit=metadata['baseline_commit'],baseline_manifest_sha256=sha(SAMPLE/'PUBLIC_SOURCE_MANIFEST.json'),files=rows))
    print('REVIEW_EXPORTED',BUILD,len(rows),flush=True)
if __name__=='__main__':main()
