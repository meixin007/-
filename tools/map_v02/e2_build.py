"""Build E2 with the unchanged E1 loader/compiler and an engineering giant fixture."""
from pathlib import Path
import argparse,copy,re,shutil,subprocess
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from e1_compile import compile_lab,compile_snapshot,sprite,rect_overlap,validate_package
from v1_build import GODOT,TEMPLATE,execute


def giant_fixture(folder):
    manifest=read(folder/'presentation.package.json')
    art=read(folder/'assets/art_bundle.json');objects=read(folder/'instances/objects.json');catalog=read(folder/'world.catalog.json');provenance=read(folder/'receipts/provenance.json')
    descriptor=copy.deepcopy(next(a for a in art['assets'] if a['asset_id']=='tree_grove'))
    descriptor.update(asset_id='tree_giant_fixture',width_m=800)
    art['assets'].append(descriptor)
    objects['objects'].append(sprite('lab.tree.giant_four_buckets',[400,800],descriptor['asset_id'],descriptor))
    for page in catalog['pages']:page['object_ids']=[o['id'] for o in objects['objects'] if rect_overlap(o['paint_bounds_m'],page['bounds_m'])]
    provenance.update(generator_version='e2_visibility_fixture_v1',postprocessor='e2_build.giant_fixture',art_files_unchanged=True,giant_is_engineering_only=True)
    for path,value in [('assets/art_bundle.json',art),('instances/objects.json',objects),('world.catalog.json',catalog),('receipts/provenance.json',provenance)]:save(folder/path,value)
    for row in manifest['files']:
        if row['kind']=='json':row['sha256']=sha(folder/row['path'])
    save(folder/'presentation.package.json',manifest)
    validate_package(folder,manifest['compatibility'])
    return manifest


def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('build id')
    scope=scope_check()
    if not scope['passed']:raise RuntimeError(scope['errors'])
    work=ROOT/'review-work/map_v02'/a.build_id;work.mkdir(parents=True,exist_ok=False)
    command=[GODOT,'--headless','--path',str(RUNTIME),'--script',str(ROOT/'tools/map_v02/e1_export_snapshot.gd'),'--','--report='+str(work/'effective_snapshot.json')]
    result=subprocess.run(command,capture_output=True,timeout=90);raw=result.stdout+result.stderr;(work/'snapshot.txt').write_bytes(raw)
    save(work/'snapshot_run.json',dict(command=command,exit_code=result.returncode))
    if result.returncode or re.search(rb'(SCRIPT ERROR:|ERROR:|WARNING:)',raw):raise RuntimeError('snapshot')
    stage=work/'SOURCE_RUNTIME';e1=stage/'v02/e1';e2=stage/'v02/e2';e1.mkdir(parents=True);e2.mkdir()
    for name in ['package_loader.gd','checks.gd']:shutil.copyfile(RUNTIME/'v02/e1'/name,e1/name)
    for path in source_files(RUNTIME/'v02/e2'):
        if path.suffix in {'.gd','.tscn'}:shutil.copyfile(path,e2/path.name)
    lab=compile_lab(e1/'packages/lab',a.build_id+'_lab');lab=giant_fixture(e1/'packages/lab')
    real=compile_snapshot(work/'effective_snapshot.json',e1/'packages/tongguan',a.build_id+'_tongguan')
    save(e1/'config.json',dict(build_id=a.build_id,packages={key:dict(path='res://v02/e1/packages/'+key,expected=m['compatibility'],build_id=m['build_id']) for key,m in [('lab',lab),('tongguan',real)]}))
    (stage/'project.godot').write_text('config_version=5\n[application]\nconfig/name="潼关 E2 可见查询"\nrun/main_scene="res://v02/e2/main.tscn"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="tongguan_v02_e2_review"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/vsync/vsync_mode=0\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    (stage/'export_presets.cfg').write_text('[preset.0]\nname="R5 Final"\nplatform="Windows Desktop"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter="*.json,*.bin"\nexclude_filter=""\n[preset.0.options]\ncustom_template/release="'+TEMPLATE.as_posix()+'"\nbinary_format/embed_pck=false\napplication/modify_resources=false\n',encoding='utf-8')
    execute(work,stage,'import',['--editor','--quit'])
    imported=(stage/'.godot/imported').resolve()
    for path in stage.rglob('*.png.import'):
        text=path.read_text(encoding='utf-8').replace('process/fix_alpha_border=true','process/fix_alpha_border=false').replace('mipmaps/generate=true','mipmaps/generate=false');path.write_text(text,encoding='utf-8')
        for rel in re.findall(r'path="res://(\.godot/imported/[^\"]+\.ctex)"',text):
            derived=(stage/rel).resolve()
            if not derived.is_relative_to(imported):raise RuntimeError('staging import escape')
            for artifact in [derived,derived.with_suffix('.md5')]:
                if artifact.is_file():artifact.unlink()
    execute(work,stage,'import_pixels',['--editor','--quit'])
    execute(work,stage,'source',['--','--e2-check','--report='+str(work/'source_result.json')])
    windows=work/'CLEAN_WINDOWS';windows.mkdir()
    execute(work,stage,'export',['--export-release','R5 Final',str(windows/'TongguanE2.exe')])
    (windows/'Start-E2.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanE2.exe"\n',encoding='ascii')
    save(work/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in sorted(windows.iterdir())})
    paths=[p for p in source_files(RUNTIME/'v02/e2') if p.name!='manifest.json']
    paths.extend([RUNTIME/'v02/e1/package_loader.gd',RUNTIME/'v02/e1/checks.gd',RUNTIME/'tests/v02/test_e2_query.gd',ROOT/'tools/map_v02/e2_build.py'])
    manifest=dict(stage='E2',build_id=a.build_id,e1_manifest_sha256=sha(RUNTIME/'v02/e1/manifest.json'),files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in sorted(paths)])
    save(work/'SOURCE_MANIFEST.json',manifest);save(RUNTIME/'v02/e2/manifest.json',manifest);save(work/'scope.json',scope)
    print('E2_BUILT',a.build_id,flush=True)


if __name__=='__main__':main()
