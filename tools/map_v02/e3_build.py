"""Fresh E3 staging; E1 immutable protocol and E2 query implementation are reused."""
import argparse,hashlib,io,re,shutil,subprocess
import numpy as np
from PIL import Image
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from e1_compile import Writer,finish,digest,canonical_fixed6,compile_lab,compile_snapshot
from e2_build import giant_fixture
from v1_build import GODOT,TEMPLATE,execute

PROFILES=dict(normal=dict(id='normal_256_320',soft=256*1024**2,hard=320*1024**2,decoded=64*1024**2,concurrency=2,attach_usec=2000,grace_usec=2000000),
    stream=dict(id='e3_stream_4_8_grace0',soft=4*1024**2,hard=8*1024**2,decoded=4*1024**2,concurrency=2,attach_usec=2000,grace_usec=0))

def terrain(bounds,core=256,gutter=4):
    x,y=np.meshgrid(bounds[0]+(np.arange(core+2*gutter)-gutter+.5)*bounds[2]/core,bounds[1]+(np.arange(core+2*gutter)-gutter+.5)*bounds[3]/core)
    water=y<730+140*np.sin(x/620)+50*np.sin(x/173)
    shade=3*np.sin(x/410)*np.cos(y/355)+2*np.sin((x+y)/83)
    rgb=np.stack([np.clip(np.where(water,wet,land)+shade,0,255).astype(np.uint8) for land,wet in [(197,145),(195,183),(160,182)]],axis=2)
    out=io.BytesIO();Image.fromarray(rgb).save(out,format='PNG');return out.getvalue()

def compile_stream(target,build_id):
    writer=Writer(target);writer.data('assets/art_bundle.json',dict(schema_version=1,assets=[]))
    coords=dict(axis='east_south',unit='meter',origin_m=[0,0])
    compat=dict(world_id='stream_lab_v02',site_id='lab.stream.proxy',layout_version='lab_8x32_e3_v1',layout_slots_sha256=digest([]),fixed_refs_sha256=digest('e3_engineering_only'),graph_version='lab_visual_no_corridors',coordinate_sha256=hashlib.sha256(canonical_fixed6(coords).encode()).hexdigest())
    pages=[]
    for level,cols,rows,span,prefix in [(0,1,1,16384,'root'),(1,4,1,4096,'parent'),(2,32,8,512,'fine')]:
        for y in range(rows):
            for x in range(cols):
                bounds=[x*span,y*span,span,4096 if level==0 else span]
                row=writer.texture(f'terrain/{prefix}_{x}_{y}.png',terrain(bounds))
                pages.append(dict(id=f'{prefix}_{x}_{y}',level=level,x=x,y=y,bounds_m=bounds,parent_id='' if level==0 else ('root_0_0' if level==1 else f'parent_{x//8}_0'),texture_files=[row['path']],texture_sha256=row['sha256'],core_px=[256,256],gutter_px=4,allowed_mip_levels=[0],optional=False))
    hashes=[r['pixel_sha256'] for r in writer.files if r['kind']=='texture']
    if len(hashes)!=len(set(hashes)):raise RuntimeError('nonunique stream content')
    total=sum(r['estimated_rgba8_bytes'] for r in writer.files if r['kind']=='texture')
    if total<3*PROFILES['stream']['soft']:raise RuntimeError('insufficient budget pressure')
    manifest=finish(writer,build_id,compat,coords,pages,[],[],dict(kind='synthetic_stream_fixture',generator_version='e3_continuous_8x32_v1',historical_content=False,unique_textures=len(hashes),unique_rgba8_bytes=total,core_px=256,reason='lower-resolution engineering pages; no new hand-painted art'),[0,0,16384,4096])
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
    stage=work/'SOURCE_RUNTIME';(stage/'v02/e1').mkdir(parents=True);(stage/'v02/e2').mkdir();(stage/'v02/e3').mkdir()
    for name in ['package_loader.gd','checks.gd']:shutil.copyfile(RUNTIME/'v02/e1'/name,stage/'v02/e1'/name)
    for name in ['source_adapter.gd','spatial_index.gd','visibility_planner.gd','submission_audit.gd','contract_checks.gd']:shutil.copyfile(RUNTIME/'v02/e2'/name,stage/'v02/e2'/name)
    for path in source_files(RUNTIME/'v02/e3'):
        if path.suffix in {'.gd','.tscn'}:shutil.copyfile(path,stage/'v02/e3'/path.name)
    packs=stage/'v02/e1/packages'
    lab=compile_lab(packs/'lab',a.build_id+'_lab');lab=giant_fixture(packs/'lab')
    real=compile_snapshot(work/'effective_snapshot.json',packs/'tongguan',a.build_id+'_tongguan')
    stream=compile_stream(packs/'stream',a.build_id+'_stream')
    config=dict(build_id=a.build_id,profiles=PROFILES,packages={key:dict(path='res://v02/e1/packages/'+key,expected=m['compatibility'],build_id=m['build_id']) for key,m in [('lab',lab),('tongguan',real),('stream',stream)]})
    save(stage/'v02/e3/config.json',config);save(stage/'v02/e1/config.json',config);save(work/'PROFILES.json',PROFILES)
    (stage/'project.godot').write_text('config_version=5\n[application]\nconfig/name="潼关 E3 流式生命周期"\nrun/main_scene="res://v02/e3/main.tscn"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="tongguan_v02_e3_review"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/vsync/vsync_mode=0\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
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
    windows=work/'CLEAN_WINDOWS';windows.mkdir()
    execute(work,stage,'export',['--export-release','R5 Final',str(windows/'TongguanE3.exe')])
    (windows/'Start-E3.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanE3.exe"\n',encoding='ascii')
    save(work/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in sorted(windows.iterdir())})
    paths=[p for p in source_files(RUNTIME/'v02/e3') if p.name!='manifest.json']
    paths.extend([RUNTIME/'v02/e1/package_loader.gd',*(RUNTIME/'v02/e2'/name for name in ['source_adapter.gd','spatial_index.gd','visibility_planner.gd','submission_audit.gd']),ROOT/'tools/map_v02/e3_build.py'])
    manifest=dict(stage='E3',build_id=a.build_id,e2_manifest_sha256=sha(RUNTIME/'v02/e2/manifest.json'),files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in sorted(paths)])
    save(work/'SOURCE_MANIFEST.json',manifest);save(RUNTIME/'v02/e3/manifest.json',manifest);save(work/'scope.json',scope)
    print('E3_BUILT',a.build_id,flush=True)

if __name__=='__main__':main()
