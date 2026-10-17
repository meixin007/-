"""Fresh E1 compiler/export staging with no legacy cache or gameplay autoload."""
from pathlib import Path
import argparse, re, shutil, subprocess, sys
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from e1_compile import compile_lab,compile_snapshot
from v1_build import GODOT,TEMPLATE,execute


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--build-id',required=True);a=parser.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('build id')
    scope=scope_check()
    if not scope['passed']:raise RuntimeError(scope['errors'])
    work=ROOT/'review-work/map_v02'/a.build_id;work.mkdir(parents=True,exist_ok=False)
    cmd=[GODOT,'--headless','--path',str(RUNTIME),'--script',str(ROOT/'tools/map_v02/e1_export_snapshot.gd'),'--','--report='+str(work/'effective_snapshot.json')]
    p=subprocess.run(cmd,capture_output=True,timeout=90);raw=p.stdout+p.stderr
    (work/'snapshot.txt').write_bytes(raw)
    save(work/'snapshot_run.json',dict(command=cmd,exit_code=p.returncode))
    if p.returncode or re.search(rb'(SCRIPT ERROR:|ERROR:|WARNING:)',raw):raise RuntimeError('snapshot')
    stage=work/'SOURCE_RUNTIME';e1=stage/'v02/e1';e1.mkdir(parents=True)
    for name in ['package_loader.gd','checks.gd','app.gd','boot.gd','main.tscn']:
        shutil.copyfile(RUNTIME/'v02/e1'/name,e1/name)
    lab=compile_lab(e1/'packages/lab',a.build_id+'_lab')
    real=compile_snapshot(work/'effective_snapshot.json',e1/'packages/tongguan',a.build_id+'_tongguan')
    config=dict(build_id=a.build_id,packages={key:dict(path='res://v02/e1/packages/'+key,expected=value['compatibility'],build_id=value['build_id']) for key,value in [('lab',lab),('tongguan',real)]})
    save(e1/'config.json',config)
    (stage/'project.godot').write_text('config_version=5\n[application]\nconfig/name="潼关 E1 分页包"\nrun/main_scene="res://v02/e1/main.tscn"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="tongguan_v02_e1_review"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/vsync/vsync_mode=0\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    (stage/'export_presets.cfg').write_text('[preset.0]\nname="R5 Final"\nplatform="Windows Desktop"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter="*.json,*.bin"\nexclude_filter=""\n[preset.0.options]\ncustom_template/release="'+TEMPLATE.as_posix()+'"\nbinary_format/embed_pck=false\napplication/modify_resources=false\n',encoding='utf-8')
    execute(work,stage,'import',['--editor','--quit'])
    for path in stage.rglob('*.png.import'):
        text=path.read_text(encoding='utf-8').replace('process/fix_alpha_border=true','process/fix_alpha_border=false').replace('mipmaps/generate=true','mipmaps/generate=false')
        path.write_text(text,encoding='utf-8')
        # External changes to .import parameters need a real reimport. Remove
        # only this fresh staging texture's derived artifacts, never old caches.
        imported=(stage/'.godot/imported').resolve()
        for resource in re.findall(r'path="res://(\.godot/imported/[^\"]+\.ctex)"',text):
            derived=(stage/resource).resolve()
            if not derived.is_relative_to(imported):raise RuntimeError('staging import path escaped')
            for artifact in [derived,derived.with_suffix('.md5')]:
                if artifact.is_file():artifact.unlink()
    execute(work,stage,'import_pixels',['--editor','--quit'])
    execute(work,stage,'source_protocol',['--','--e1-check','--report='+str(work/'source_protocol_result.json')])
    windows=work/'CLEAN_WINDOWS';windows.mkdir()
    execute(work,stage,'export',['--export-release','R5 Final',str(windows/'TongguanE1.exe')])
    (windows/'Start-E1.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanE1.exe"\n',encoding='ascii')
    save(work/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in sorted(windows.iterdir())})
    names=[p for p in source_files(RUNTIME/'v02/e1') if p.name!='manifest.json']
    names.extend([ROOT/'tools/map_v02'/n for n in ['e1_compile.py','e1_build.py','e1_export_snapshot.gd','test_e1_package.py']])
    names.append(RUNTIME/'tests/v02/test_e1_package.gd')
    manifest=dict(stage='E1',build_id=a.build_id,s0_manifest_sha256=sha(ROOT/'samples/tongguan_v01/V02_SOURCE_MANIFEST.json'),v1_manifest_sha256=sha(RUNTIME/'v02/v1/manifest.json'),visual_acceptance_sha256=sha(ROOT/'reports/map_v02/V1_A01_ACCEPTED_20261016.json'),files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in sorted(names)])
    save(work/'SOURCE_MANIFEST.json',manifest);save(RUNTIME/'v02/e1/manifest.json',manifest);save(work/'scope.json',scope)
    print('E1_BUILT',a.build_id,flush=True)


if __name__=='__main__':main()
