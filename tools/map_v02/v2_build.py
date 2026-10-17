"""Isolated V2 review build; original sources/receipts and art stay byte-exact."""
import argparse,re,shutil
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_build import execute,TEMPLATE
def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('id')
    scope=scope_check()
    if not scope['passed']:raise RuntimeError(scope['errors'])
    work=ROOT/'review-work/map_v02'/a.build_id;work.mkdir(parents=True,exist_ok=False)
    stage=work/'SOURCE_RUNTIME';stage.mkdir()
    for source in source_files(RUNTIME):
        target=stage/source.relative_to(RUNTIME);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    project=stage/'project.godot';text=project.read_text(encoding='utf-8').replace('run/main_scene="res://main.tscn"','run/main_scene="res://v02/v2/main.tscn"').replace('Session="*res://army/session.gd"','Session="*res://v02/v2/session.gd"').replace('tongguan_slice_v01_final','tongguan_v02_v2_review');project.write_text(text,encoding='utf-8')
    cfg=stage/'export_presets.cfg';cfg.write_text(cfg.read_text(encoding='utf-8').replace('custom_template/release=""','custom_template/release="'+TEMPLATE.as_posix()+'"'),encoding='utf-8')
    execute(work,stage,'import',['--editor','--quit'])
    imported=(stage/'.godot/imported').resolve()
    for path in (stage/'v02').rglob('*.png.import'):
        text=path.read_text(encoding='utf-8').replace('process/fix_alpha_border=true','process/fix_alpha_border=false').replace('mipmaps/generate=false','mipmaps/generate=true');path.write_text(text,encoding='utf-8')
        for rel in re.findall(r'path="res://(\.godot/imported/[^\"]+\.ctex)"',text):
            generated=(stage/rel).resolve()
            if not generated.is_relative_to(imported):raise RuntimeError('import escape')
            for file in [generated,generated.with_suffix('.md5')]:
                if file.is_file():file.unlink()
    execute(work,stage,'import_pixels',['--editor','--quit'])
    windows=work/'CLEAN_WINDOWS';windows.mkdir()
    execute(work,stage,'export',['--export-release','R5 Final',str(windows/'TongguanV2.exe')])
    (windows/'Start-V2.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanV2.exe"\n',encoding='ascii')
    save(work/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in windows.iterdir()})
    files=[p for p in source_files(RUNTIME/'v02/v2') if p.name!='manifest.json']
    manifest=dict(stage='V2',build_id=a.build_id,status='candidate_pending_user_review',v1_manifest_sha256=sha(RUNTIME/'v02/v1/manifest.json'),files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in files])
    save(work/'SOURCE_MANIFEST.json',manifest);save(RUNTIME/'v02/v2/manifest.json',manifest);save(work/'scope.json',scope)
    print('V2_BUILT',a.build_id,flush=True)
if __name__=='__main__':main()
