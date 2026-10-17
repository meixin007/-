"""Fresh C1 staging and clean Windows export; earlier candidates stay sealed."""
import argparse,re,shutil,subprocess
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from c1_compile import compile_real,compile_multi
from e3_build import PROFILES
from v1_build import GODOT,TEMPLATE,execute

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('build id')
    scope=scope_check()
    if not scope['passed']:raise RuntimeError(scope['errors'])
    work=ROOT/'review-work/map_v02'/a.build_id;work.mkdir(parents=True,exist_ok=False)
    cmd=[GODOT,'--headless','--path',str(RUNTIME),'--script',str(ROOT/'tools/map_v02/e1_export_snapshot.gd'),'--','--report='+str(work/'effective_snapshot.json')]
    proc=subprocess.run(cmd,capture_output=True,timeout=90);raw=proc.stdout+proc.stderr;(work/'snapshot.txt').write_bytes(raw)
    save(work/'snapshot_run.json',dict(command=cmd,exit_code=proc.returncode))
    if proc.returncode or re.search(rb'(SCRIPT ERROR:|ERROR:|WARNING:)',raw):raise RuntimeError('snapshot')
    stage=work/'SOURCE_RUNTIME';stage.mkdir()
    for path in source_files(RUNTIME):
        target=stage/path.relative_to(RUNTIME);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
    packs=stage/'v02/c1/packages'
    real=compile_real(work/'effective_snapshot.json',packs/'tongguan',a.build_id+'_tongguan')
    multi=compile_multi(packs/'multi',a.build_id+'_multi')
    # Test-only monolithic reference, never requested by the interactive service.
    from c1_compile import combined,encoded
    from PIL import Image
    reference=Image.new('RGBA',(4160,3136))
    base=RUNTIME/'v02/relief_r01/assets'
    for y in range(3):
        for x in range(4):reference.paste(combined(base/f'ground_{x}_{y}.png',base/f'water_{x}_{y}.png'),(x*1024,y*1024))
    (stage/'v02/c1/reference_fine.png').write_bytes(encoded(reference))
    profiles=dict(normal=PROFILES['normal'],pressure=dict(id='c1_pressure_32_48',soft=32*1024**2,hard=48*1024**2,decoded=24*1024**2,concurrency=2,attach_usec=2000,grace_usec=0))
    config=dict(build_id=a.build_id,profiles=profiles,packages={key:dict(path='res://v02/c1/packages/'+key,expected=m['compatibility'],build_id=m['build_id']) for key,m in [('tongguan',real),('multi',multi)]},semantic=dict(reference_width_m=1200,thresholds_px=[32,128,384],hysteresis=.15,transition_msec=180,label_limit=64),visual='pending',q1='not_claimed')
    save(stage/'v02/c1/config.json',config);save(work/'PROFILES.json',config)
    project=stage/'project.godot';text=project.read_text(encoding='utf-8').replace('run/main_scene="res://main.tscn"','run/main_scene="res://v02/c1/main.tscn"').replace('Session="*res://army/session.gd"','Session="*res://v02/v2/session.gd"').replace('tongguan_slice_v01_final','tongguan_v02_c1_review').replace('config/name="潼关 v0.1 最终验收"','config/name="潼关 C1 流式整合 待审阅"');project.write_text(text,encoding='utf-8')
    cfg=stage/'export_presets.cfg';cfg.write_text(cfg.read_text(encoding='utf-8').replace('custom_template/release=""','custom_template/release="'+TEMPLATE.as_posix()+'"'),encoding='utf-8')
    execute(work,stage,'import',['--editor','--quit'])
    imported=(stage/'.godot/imported').resolve()
    for path in (stage/'v02/c1/packages').rglob('*.png.import'):
        text=path.read_text(encoding='utf-8').replace('process/fix_alpha_border=true','process/fix_alpha_border=false').replace('mipmaps/generate=true','mipmaps/generate=false');path.write_text(text,encoding='utf-8')
        for rel in re.findall(r'path="res://(\.godot/imported/[^\"]+\.ctex)"',text):
            derived=(stage/rel).resolve()
            if not derived.is_relative_to(imported):raise RuntimeError('staging import escape')
            for artifact in [derived,derived.with_suffix('.md5')]:
                if artifact.is_file():artifact.unlink()
    execute(work,stage,'import_pixels',['--editor','--quit'])
    windows=work/'CLEAN_WINDOWS';windows.mkdir()
    execute(work,stage,'export',['--export-release','R5 Final',str(windows/'TongguanC1.exe')])
    (windows/'Start-C1.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanC1.exe"\n',encoding='ascii')
    save(work/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in windows.iterdir()})
    inputs=[p for p in source_files(RUNTIME/'v02/c1') if p.name!='manifest.json']+[ROOT/'tools/map_v02/c1_build.py',ROOT/'tools/map_v02/c1_compile.py',RUNTIME/'tests/v02/c1_policy_runner.gd']
    save(work/'SOURCE_MANIFEST.json',dict(build_id=a.build_id,visual='pending',files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in sorted(inputs)],reused_e1_sha256=sha(RUNTIME/'v02/e1/package_loader.gd'),reused_e2_sha256=sha(RUNTIME/'v02/e2/visibility_planner.gd'),reused_e3_sha256=sha(RUNTIME/'v02/e3/residency_manager.gd')))
    save(work/'scope.json',scope);print('C1_BUILT',a.build_id,flush=True)
if __name__=='__main__':main()
