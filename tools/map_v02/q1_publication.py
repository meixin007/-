"""Real Windows version files, fault injection, activation, native restart and rollback."""
import argparse,copy,hashlib,io,json,shutil,subprocess
import numpy as np
from PIL import Image
from common import ROOT,read,save,sha
import e1_compile as compiler
from q1_evidence import write_version,activate,activate_review,rollback,validate_version
from q1_run import run

def incremental(out):
    old=out/'incremental_old';new=out/'incremental_new';old_manifest=compiler.compile_lab(old,'q1_local_old')
    catalog=read(old/'world.catalog.json');patch=[-920,-920,64,64];reused=[];missing_unchanged=[];recomputed=[];original=compiler.lab_texture
    by_bounds={tuple(row['bounds_m']):row for row in catalog['pages']}
    def changed_texture(bounds,core=256,gutter=4):
        row=by_bounds[tuple(bounds)];region=[bounds[0]-bounds[2]*gutter/core,bounds[1]-bounds[3]*gutter/core,bounds[2]*(core+2*gutter)/core,bounds[3]*(core+2*gutter)/core]
        if not compiler.rect_overlap(region,patch):
            source=old/row['texture_files'][0][:-4]
            if source.exists():reused.append(row['id']);return source.read_bytes()
            missing_unchanged.append(row['id']);return original(bounds,core,gutter)
        image=Image.open(io.BytesIO(original(bounds,core,gutter))).convert('RGBA');a=np.array(image);x,y=np.meshgrid(bounds[0]+(np.arange(core+2*gutter)-gutter+.5)*bounds[2]/core,bounds[1]+(np.arange(core+2*gutter)-gutter+.5)*bounds[3]/core)
        mask=(x>=patch[0])&(x<patch[0]+patch[2])&(y>=patch[1])&(y<patch[1]+patch[3]);a[mask,:3]=[170,155,130];stream=io.BytesIO();Image.fromarray(a).save(stream,format='PNG');recomputed.append(row['id']);return stream.getvalue()
    compiler.lab_texture=changed_texture
    try:manifest=compiler.compile_lab(new,'q1_local_new')
    finally:compiler.lab_texture=original
    next_catalog=read(new/'world.catalog.json');changes=[];identical=[]
    for before,after in zip(catalog['pages'],next_catalog['pages']):
        if before['texture_sha256']==after['texture_sha256']:identical.append(before['id'])
        else:changes.append(before['id'])
    expected=['root_0_0','parent_0_0','fine_0_0']
    if set(changes)!=set(expected) or len(reused)!=17 or len(missing_unchanged)!=1:raise AssertionError(('local page closure',changes,reused))
    # Moving a dynamic object changes old/new memberships, never terrain pixels.
    objects=read(new/'instances/objects.json');old_record=copy.deepcopy(objects['objects'][0]);objects['objects'][0]=compiler.relocate(old_record,[600,0])
    for page in next_catalog['pages']:page['object_ids']=[row['id'] for row in objects['objects'] if compiler.rect_overlap(row['paint_bounds_m'],page['bounds_m'])]
    save(new/'instances/objects.json',objects);save(new/'world.catalog.json',next_catalog)
    for row in manifest['files']:
        if row['path'] in ['instances/objects.json','world.catalog.json']:row['sha256']=sha(new/row['path'])
    save(new/'presentation.package.json',manifest);compiler.validate_package(new,manifest['compatibility'])
    affected=[p['id'] for p in next_catalog['pages'] if compiler.rect_overlap(old_record['paint_bounds_m'],p['bounds_m']) or compiler.rect_overlap(objects['objects'][0]['paint_bounds_m'],p['bounds_m'])]
    return dict(passed=True,patch_bounds_m=patch,changed_page_ids=changes,unchanged_page_identities=identical,reused_without_terrain_regeneration=reused,declared_optional_missing_unchanged=missing_unchanged,parent_dependency_closure=expected,dynamic_move_affected=affected,old_position=old_record['position_m'],new_position=objects['objects'][0]['position_m'],terrain_not_rebaked_for_dynamic_move=True,raw_old_manifest=old_manifest,new_manifest=manifest)

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args();work=ROOT/'review-work/map_v02'/a.build_id;out=work/'publication';out.mkdir(exist_ok=False)
    old_root=ROOT/'review-work/releases/tongguan_v01_revfix_20261015_02/Windows';new_root=work/'CLEAN_WINDOWS'
    expected_old=read(old_root.parent/'RELEASE.json')['artifacts']
    for name in ['TongguanFinal.exe','TongguanFinal.pck']:
        if sha(old_root/name)!=expected_old[name]['sha256']:raise RuntimeError('old release changed')
    trial=out/'switch_trial';trial.mkdir();old_files={name:(old_root/name).read_bytes() for name in ['TongguanFinal.exe','TongguanFinal.pck']};new_files={name:(new_root/name).read_bytes() for name in ['TongguanQ1.exe','TongguanQ1.pck']}
    write_version(trial,'old',old_files);write_version(trial,'new',new_files);activate(trial,'old');before=(trial/'active.json').read_bytes();cases=[]
    # Incomplete extraction, tampering and write failure are kept out of activation.
    partial=trial/'versions/partial';partial.mkdir();(partial/'TongguanQ1.exe').write_bytes(new_files['TongguanQ1.exe'])
    for version,fault in [('partial',None),('new','disk_full'),('new','before_replace')]:
        caught=None
        try:activate(trial,version,fault=fault)
        except (ValueError,OSError) as error:caught=str(error)
        if caught is None or (trial/'active.json').read_bytes()!=before:raise AssertionError('old pointer lost')
        cases.append(dict(case=version+'_'+str(fault),caught=caught,old_pointer_unchanged=True))
    bad=trial/'versions/new/TongguanQ1.pck';bad.write_bytes(b'broken')
    try:activate(trial,'new');raise AssertionError('corruption accepted')
    except ValueError as error:cases.append(dict(case='corrupt_new_pack',error=str(error),old_pointer_unchanged=(trial/'active.json').read_bytes()==before))
    bad.write_bytes(new_files['TongguanQ1.pck'])
    rejected=activate_review(trial,'new',False)
    if rejected['ok'] or (trial/'active.json').read_bytes()!=before:raise AssertionError('style rejection changed pointer')
    cases.append(dict(case='style_migration_rejected',result=rejected,old_pointer_unchanged=True))
    # Native old packaged process actually starts before and after rollback.
    old_exe=trial/'versions/old/TongguanFinal.exe';starts=[]
    def old_probe(tag):
        result=out/(tag+'.json');command=[str(old_exe),'--headless','--log-file',str(out/(tag+'.log')),'--','--probe-build','--report='+str(result)]
        run_result=subprocess.run(command,cwd=old_exe.parent,capture_output=True,timeout=45);(out/(tag+'.txt')).write_bytes(run_result.stdout+run_result.stderr)
        value=read(result) if result.exists() else {}
        if run_result.returncode or value.get('build_id')!='tongguan_v01_revfix_20261015_02' or not value.get('release'):raise AssertionError('old packaged restart')
        starts.append(dict(command=command,exit_code=run_result.returncode,result=value))
    old_probe('old_before')
    activate_review(trial,'new',True);new_smoke=run(a.build_id,'installed_smoke','smoke',exe=trial/'versions/new/TongguanQ1.exe')
    if not new_smoke['execution_passed']:raise AssertionError('installed new release smoke failed')
    rollback(trial)
    if (trial/'active.json').read_bytes()!=before:raise AssertionError('rollback mismatch')
    old_probe('old_after_rollback')
    local=incremental(out);save(out/'incremental.json',local)
    save(out/'result.json',dict(passed=True,cases=cases,old_native_starts=starts,new_installed_smoke='installed_smoke/result.json',rollback_exact_pointer=True,old_releases_sha_unchanged=all(sha(old_root/name)==expected_old[name]['sha256'] for name in old_files),incremental_passed=local['passed'],disk_full_scope='injected ENOSPC at write boundary, not physical volume exhaustion',atomic_replace_api='os.replace on the actual Windows filesystem; old/new executable and PCK checksums validated before pointer change',no_existing_active_pointer_modified=True));print('Q1_PUBLICATION PASS',flush=True)
if __name__=='__main__':main()
