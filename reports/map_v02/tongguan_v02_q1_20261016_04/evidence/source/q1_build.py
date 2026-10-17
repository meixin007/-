"""Versioned Q1 build around the accepted C1 source/art; no existing file is edited."""
import argparse,re,shutil
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_build import execute,TEMPLATE
from e1_compile import compile_lab
from e2_build import giant_fixture
from e3_build import compile_stream,PROFILES
from q1_fixtures import compile_sites
from q1_ab_compile import compile_ab

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('build id')
    if not scope_check()['passed']:raise RuntimeError(scope_check()['errors'])
    accepted=ROOT/'review-work/map_v02/tongguan_v02_c1_20261016_04';work=ROOT/'review-work/map_v02'/a.build_id;work.mkdir(parents=True,exist_ok=False);stage=work/'SOURCE_RUNTIME';stage.mkdir()
    for source in source_files(accepted/'SOURCE_RUNTIME'):
        target=stage/source.relative_to(accepted/'SOURCE_RUNTIME');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    for source in source_files(RUNTIME/'v02/q1'):
        target=stage/'v02/q1'/source.relative_to(RUNTIME/'v02/q1');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    packs=stage/'v02/q1/packages'
    lab=compile_lab(packs/'lab',a.build_id+'_lab');lab=giant_fixture(packs/'lab')
    stream=compile_stream(packs/'stream',a.build_id+'_stream')
    sites=compile_sites(packs/'sites',a.build_id+'_sites',32)
    labels=compile_sites(packs/'labels',a.build_id+'_labels',2000)
    ab=compile_ab(packs/'ab',a.build_id+'_ab',read(accepted/'effective_snapshot.json'))
    config=read(stage/'v02/c1/config.json');config['q1_build_id']=a.build_id
    config['profiles']['stream']=PROFILES['stream']
    for key,m in [('lab',lab),('stream',stream),('sites',sites),('labels',labels),('ab',ab)]:config['packages'][key]=dict(path='res://v02/q1/packages/'+key,expected=m['compatibility'],build_id=m['build_id'])
    save(stage/'v02/c1/config.json',config);save(stage/'v02/q1/config.json',config)
    project=stage/'project.godot';text=project.read_text(encoding='utf-8').replace('res://v02/c1/main.tscn','res://v02/q1/main.tscn').replace('tongguan_v02_c1_review','tongguan_v02_q1_validation').replace('潼关 C1 流式整合 待审阅','潼关 v0.2 Q1 验证');project.write_text(text,encoding='utf-8')
    execute(work,stage,'import',['--editor','--quit'])
    imported=(stage/'.godot/imported').resolve()
    for path in stage.rglob('*.png.import'):
        text=path.read_text(encoding='utf-8').replace('process/fix_alpha_border=true','process/fix_alpha_border=false').replace('mipmaps/generate=true','mipmaps/generate=false');path.write_text(text,encoding='utf-8')
        for rel in re.findall(r'path="res://(\.godot/imported/[^\"]+\.ctex)"',text):
            generated=(stage/rel).resolve()
            if not generated.is_relative_to(imported):raise RuntimeError('staging import escape')
            for derived in [generated,generated.with_suffix('.md5')]:
                if derived.is_file():derived.unlink()
    execute(work,stage,'import_pixels',['--editor','--quit'])
    windows=work/'CLEAN_WINDOWS';windows.mkdir()
    execute(work,stage,'export',['--export-release','R5 Final',str(windows/'TongguanQ1.exe')])
    (windows/'Start-Q1.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanQ1.exe"\n',encoding='ascii')
    save(work/'ARTIFACTS.json',{p.name:dict(sha256=sha(p),bytes=p.stat().st_size) for p in windows.iterdir()})
    save(work/'SOURCE_MANIFEST.json',dict(build_id=a.build_id,accepted_c1_build='tongguan_v02_c1_20261016_04',accepted_c1_receipt_sha256=sha(ROOT/'reports/map_v02/C1_A01_ACCEPTED_20261016.json'),files=[dict(path=f.relative_to(ROOT).as_posix(),sha256=sha(f)) for f in source_files(RUNTIME/'v02/q1')],accepted_c1_manifest=read(accepted/'SOURCE_MANIFEST.json')))
    save(work/'PROFILES.json',config);print('Q1_BUILT',a.build_id,flush=True)
if __name__=='__main__':main()
