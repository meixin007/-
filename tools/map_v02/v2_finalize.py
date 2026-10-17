"""Seal V2 as pending visual review, never auto-accept its art."""
import argparse,re,shutil,sys,zipfile
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_finalize import run
def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;report=ROOT/'reports/map_v02'/a.build_id;report.mkdir(parents=True,exist_ok=False);evidence=report/'evidence';evidence.mkdir()
    native=read(work/'native_01/result.json')
    if not native['technical_passed'] or not read(ROOT/'review-work/map_v02/v2_regressions/summary.json')['passed']:raise RuntimeError('validation failed')
    for row in read(work/'SOURCE_MANIFEST.json')['files']:
        path=ROOT/row['path']
        if sha(path)!=row['sha256'] or sha(work/'SOURCE_RUNTIME'/path.relative_to(RUNTIME))!=row['sha256']:raise RuntimeError('source/staged mismatch')
    for name,row in read(work/'ARTIFACTS.json').items():
        if sha(work/'CLEAN_WINDOWS'/name)!=row['sha256'] or name in native['artifacts'] and native['artifacts'][name]!=row['sha256']:raise RuntimeError('artifact mismatch')
    before=read(ROOT/'review-work/map_v02/v2_boundary/before.json')['files'];changed=[row['path'] for row in before if not (ROOT/row['path']).is_file() or sha(ROOT/row['path'])!=row['sha256']]
    save(evidence/'protection.json',dict(passed=not changed,files=len(before),changed=changed))
    if changed:raise RuntimeError('old content changed')
    shutil.copytree(work/'native_01',report/'native',ignore=shutil.ignore_patterns('*.log'))
    shutil.copytree(ROOT/'review-work/map_v02/v2_boundary',evidence/'development')
    shutil.copytree(ROOT/'review-work/map_v02/v2_regressions',evidence/'regressions')
    for name in ['SOURCE_MANIFEST.json','ARTIFACTS.json','import.json','import.txt','import_pixels.json','import_pixels.txt','export.json','export.txt']:shutil.copyfile(work/name,evidence/name)
    run(evidence,'repository',[sys.executable,'verify_repository.py']);run(evidence,'plugin_source',[sys.executable,'plugin-source/verify_source.py']);run(evidence,'sealed_protection',[sys.executable,'tools/verify_review_protection.py']);run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise RuntimeError(scope['errors'])
    save(report/'visual_review.json',dict(build_id=a.build_id,status='pending',author='awaiting_user',cameras=['composition','courtyard','wall','shore'],asset_manifest_sha256=sha(RUNTIME/'v02/v2/assets.json'),source_manifest_sha256=sha(work/'SOURCE_MANIFEST.json'),opinion=None))
    save(report/'visual_migration.json',dict(status='candidate_pending_user_review',scope='new isolated V2 work copy only',old_sources_written=False,old_protected_pixels_written=False,base_v1='tongguan_v02_v1_20261015_04',terrain_bounds_m=[-1024,-1024,2048,1536],preview_trees=13,original_source_trees=72,reject_action='close V2 and launch unchanged V1 or legacy package',new_assets=3))
    shutil.copyfile(RUNTIME/'v02/v2/assets.json',report/'assets.json');shutil.copyfile(RUNTIME/'v02/v2/generation_prompts.json',report/'generation_prompts.json')
    extras=[*(ROOT/'tools/map_v02').glob('v2_*.py'),ROOT/'docs/map_v02/V2_REVIEW.md',RUNTIME/'tests/v02/test_v2_presentation.gd']
    save(evidence/'supplemental_sources.json',dict(files=[dict(path=f.relative_to(ROOT).as_posix(),sha256=sha(f)) for f in sorted(extras)]))
    archive=work/(a.build_id+'_windows.zip')
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
        for path in sorted((work/'CLEAN_WINDOWS').iterdir()):z.write(path,path.name)
    with zipfile.ZipFile(archive) as z:
        if z.testzip()!=None:raise RuntimeError('zip CRC')
    save(evidence/'archive.json',dict(path=str(archive),sha256=sha(archive),bytes=archive.stat().st_size))
    content=f'''# V2 Godot组合审阅候选

构建 `{a.build_id}`，视觉状态 **pending**。新增坡岸/院落/墙段与已有建设、成长、损毁、修复的组合入口；原地图、素材、八地块、ID及封存交付不覆盖。技术验证通过不代签美术审阅。

启动 [Start-V2.cmd](H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/CLEAN_WINDOWS/Start-V2.cmd)。可编辑Godot工程为同目录SOURCE_RUNTIME/project.godot，组合场景SOURCE_RUNTIME/v02/v2/composition.tscn。按1—4切关河、院落、墙楼、坡岸；G看地块/接点，T地形独显，B切13组已接受V1小样林簇。拖动/滚轮平移缩放。

初始已通过原服务完成仓库示例：实付120钱/20木、3天。可按“回到建设前”→“报价并建造仓库”→推进3天；点“仓库＋墙段损毁”查看实际塌顶与缺口，再点“原位修复”。修复沿用已有set_damage状态接口，不增加维修价格、工期或战斗。可切原成长档位与主关控制。所有运行进度仅在新user://tests/v02/v2/<unique-run>检查点。

## 同机位证据

![原位损毁](native/courtyard_damaged.png)

![原位修复](native/courtyard_repaired.png)

![墙段缺口](native/wall_damaged.png)

另有组合、坡岸、地形独显、建设前/中/后、三档成长与12帧连续相机序列，保存在native/，均为实际1920×1080 Godot读回，无后期修图。地图区修复前后逐像素相同，ID、位置、比例、接地点、合同和已付资源不变。

## 资产与迁移

仅用内置image_gen补3张必要PNG，未批量扩充。素材及SHA见[assets.json](assets.json)，完整执行规格/提示集见[generation_prompts.json](generation_prompts.json)：

- [仓库塌顶](H:/tongguan_reviewfix_20261015/samples/tongguan_v01/runtime/v02/v2/assets/warehouse_damaged_v01.png)
- [墙段缺口](H:/tongguan_reviewfix_20261015/samples/tongguan_v01/runtime/v02/v2/assets/wall_damaged_v01.png)
- [驻军院落](H:/tongguan_reviewfix_20261015/samples/tongguan_v01/runtime/v02/v2/assets/barracks_v01.png)

三图均1536×1024透明画布，固定方向/原锚点/同一光向；仓库与墙完整态继续直接用原V1文件。损毁1/2共用一张受损图，驻军损毁变体不在本有限小样内；其它建筑门类不扩图。生成图保持原注册坐标，但其形制与像素对齐仍由作者审阅，不能以程序变换一致代替视觉判断。

V1的坡岸、水、道路、关楼、墙和13组已接受小样林簇继续用于本候选。原72实例仍按原发布ID/位置读取；13组小样林簇另标v1.preview.*，只在新审阅副本显示，不是新增正式地图数据。新风格迁移范围见[visual_migration.json](visual_migration.json)，保持pending；拒绝时直接回旧包，旧锁区像素不变。

## 技术与保护

- 当前源码契约23项、原生{native['checks']}项通过；退出0，无超时、ERROR/WARNING/资源泄漏诊断。原生包括实际纹理切换、建设/资金/木料、同机位像素恢复、稳定身份/变换、Save22恢复、相机只读、成长/关门独立性及原72实例/13小样分离。
- 原建设、owner、发布、通道及存档回归均通过；存档明确使用原TONGGUAN_R5_FIXTURES夹具。仓库范围、插件空素材注册表、旧封存与空白检查通过。
- 开工前{len(before)}个已有文件SHA全部不变。原主工程/历史开发目录未写；旧地图/PNG/注册表/保存格式/通道几何未改，未提交、推送或发布。
- 唯一GameState/Context由原FinalController创建；新Session不初始化旧视觉缓存。V2场景表现与E3正式合流留给C1；不宣称E3离屏玩法已在本入口整合，也不宣称Q1性能或历史通过。

作者意见仍为空：[visual_review.json](visual_review.json)。本批停止在可操作候选审阅，未签署视觉接受、未启动下一批。构建01原生102项通过；02保留已接受V1林簇并增加来源分离检查，为本次交付。
'''
    (report/'REPORT.md').write_text(content,encoding='utf-8')
    save(report/'ACCEPTANCE.json',dict(stage='V2',build_id=a.build_id,technical='passed',native_checks=native['checks'],visual='pending',old_files_unchanged=True,c1='not_implemented',q1='not_claimed'))
    save(report/'DELIVERY_MANIFEST.json',dict(build_id=a.build_id,files=[dict(path=f.relative_to(report).as_posix(),sha256=sha(f),bytes=f.stat().st_size) for f in source_files(report) if f.name!='DELIVERY_MANIFEST.json']))
    print('V2_READY',report,flush=True)
if __name__=='__main__':main()
