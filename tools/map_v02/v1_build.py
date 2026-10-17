"""Export an isolated V1 composition without changing S0 files or receipts."""
from pathlib import Path
import argparse, shutil, re, os, subprocess, sys, json
from common import ROOT,RUNTIME,BASE,read,save,sha,source_files,scope_check,git
GODOT=os.environ.get('GODOT_BIN',r'H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe')
TEMPLATE=Path(r'H:\godot4.61\export_templates_extract\templates\windows_release_x86_64.exe')
def execute(dest,base,name,args):
    cmd=[GODOT,'--headless','--path',str(base),*args]
    p=subprocess.run(cmd,capture_output=True,timeout=160);raw=p.stdout+p.stderr
    (dest/(name+'.txt')).write_bytes(raw)
    errors=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',raw.decode('utf-8',errors='replace'),re.M)
    save(dest/(name+'.json'),dict(command=cmd,exit_code=p.returncode,diagnostics=errors))
    if p.returncode or errors:raise RuntimeError(str(dest/(name+'.txt')))
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--build-id',required=True);a=parser.parse_args()
    if not re.fullmatch('[a-zA-Z0-9_-]+',a.build_id):raise ValueError('build id')
    scope=scope_check()
    if not scope['passed']:raise RuntimeError(scope['errors'])
    dest=ROOT/'review-work/map_v02'/a.build_id;dest.mkdir(parents=True,exist_ok=False)
    v1=RUNTIME/'v02/v1'
    manifest=dict(stage='V1',build_id=a.build_id,style_id=read(v1/'style.json')['style_id'],
      s0_manifest_sha256=sha(ROOT/'samples/tongguan_v01/V02_SOURCE_MANIFEST.json'),
      files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in source_files(v1) if p.name!='manifest.json'])
    save(v1/'manifest.json',manifest)
    staging=dest/'SOURCE_RUNTIME';staging.mkdir()
    for p in source_files(RUNTIME):
        target=staging/p.relative_to(RUNTIME);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
    project=staging/'project.godot'
    text=project.read_text(encoding='utf-8').replace('run/main_scene="res://main.tscn"','run/main_scene="res://v02/v1/main.tscn"').replace('tongguan_slice_v01_final','tongguan_v02_v1_review')
    project.write_text(text,encoding='utf-8')
    cfg=staging/'export_presets.cfg';text=cfg.read_text(encoding='utf-8').replace('custom_template/release=""','custom_template/release="'+TEMPLATE.as_posix()+'"');cfg.write_text(text,encoding='utf-8')
    save(staging/'v02/v1/build.json',dict(build_id=a.build_id,stage='V1',manifest_sha256=sha(v1/'manifest.json'),style_sha256=sha(v1/'style.json'),source_parent=git('rev-parse','HEAD'),visual_acceptance='pending'))
    execute(dest,staging,'import',['--editor','--quit'])
    for p in (staging/'v02/v1/assets').rglob('*.png.import'):
        p.write_text(p.read_text(encoding='utf-8').replace('mipmaps/generate=false','mipmaps/generate=true'),encoding='utf-8')
    execute(dest,staging,'import_mips',['--editor','--quit'])
    windows=dest/'Windows';windows.mkdir()
    execute(dest,staging,'export',['--export-release','R5 Final',str(windows/'TongguanV1.exe')])
    (windows/'Start-V1.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanV1.exe"\n',encoding='ascii')
    save(dest/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in windows.iterdir()})
    save(dest/'scope.json',scope);shutil.copyfile(v1/'manifest.json',dest/'SOURCE_MANIFEST.json')
    print('V1_BUILT',a.build_id,flush=True)
if __name__=='__main__':main()
