"""Seal E2 source/native/query evidence without changing earlier deliveries."""
import argparse,importlib.metadata,re,shutil,sys,zipfile
from jsonschema import Draft202012Validator
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_finalize import run


def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;report=ROOT/'reports/map_v02'/a.build_id
    report.mkdir(parents=True,exist_ok=False);evidence=report/'evidence';evidence.mkdir()
    native=read(work/'native_01/result.json');source=read(work/'source_result.json')
    if not native['technical_passed'] or source['failures']:raise RuntimeError('source or native failure')
    for row in read(work/'SOURCE_MANIFEST.json')['files']:
        if sha(ROOT/row['path'])!=row['sha256']:raise RuntimeError('source changed '+row['path'])
    for path in source_files(RUNTIME/'v02/e2'):
        if path.suffix in {'.gd','.tscn'} and sha(path)!=sha(work/'SOURCE_RUNTIME/v02/e2'/path.name):raise RuntimeError('staged source changed')
    for name,row in read(work/'ARTIFACTS.json').items():
        if sha(work/'CLEAN_WINDOWS'/name)!=row['sha256']:raise RuntimeError('artifact changed')
        if name in native['artifacts'] and native['artifacts'][name]!=row['sha256']:raise RuntimeError('tested artifact changed')
    for name in ['SOURCE_MANIFEST.json','ARTIFACTS.json','effective_snapshot.json','snapshot.txt','snapshot_run.json','source.json','source.txt','source_result.json','export.json','export.txt','import.json','import.txt','import_pixels.json','import_pixels.txt']:
        shutil.copyfile(work/name,evidence/name)
    shutil.copytree(work/'native_01',report/'native',ignore=shutil.ignore_patterns('*.log'))
    boundary=ROOT/'review-work/map_v02/e2_boundary'
    shutil.copytree(boundary,evidence/'development')
    regression=ROOT/'review-work/map_v02/e2_regressions'
    shutil.copytree(regression,evidence/'regressions')
    legacy=read(regression/'summary.json')
    cases=[r for r in legacy['tests'] if r['name']!='e2_core']
    final_core=read(boundary/'final_source_run.json')
    cases.append(dict(name='current_e2_core',passed=final_core['passed'],command=final_core['command'],exit_code=final_core['exit_code'],diagnostics=final_core['diagnostics']))
    if not all(r['passed'] for r in cases):raise RuntimeError('regressions')
    save(evidence/'regressions_final.json',dict(passed=True,tests=cases))
    before=read(boundary/'before.json')['files']
    changed=[r['path'] for r in before if not (ROOT/r['path']).is_file() or sha(ROOT/r['path'])!=r['sha256']]
    save(evidence/'protection.json',dict(passed=not changed,files=len(before),changed=changed))
    if changed:raise RuntimeError('pre-E2 files changed')
    matrix=native['core']['observations']
    save(report/'QUERY_MATRIX.json',dict(scope='metadata only; no frame-time/capacity claim',rows=matrix))
    save(report/'NATIVE_COMPARISONS.json',dict(observations=native['observations']))
    schema=read(ROOT/'schemas/map_v02/presentation_package.schema.json');validator=Draft202012Validator(schema)
    package_dir=work/'SOURCE_RUNTIME/v02/e1/packages';packages=[]
    for name in ['lab','tongguan']:
        folder=package_dir/name;manifest=read(folder/'presentation.package.json')
        errors=[e.message for e in validator.iter_errors(manifest)]
        if errors:raise RuntimeError(errors)
        for path in folder.rglob('*.json'):
            target=evidence/'packages'/name/path.relative_to(folder);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
        packages.append(dict(name=name,manifest_sha256=sha(folder/'presentation.package.json'),schema_passed=True))
    snapshot=read(work/'effective_snapshot.json');objects=read(package_dir/'tongguan/instances/objects.json')['objects']
    raw=[o for o in objects if o.get('source_record')]
    preserved=sorted(o['id'] for o in raw)==sorted(snapshot['raw_instance_ids']) and all(o['id']==o['source_record']['id'] and o['position_m']==o['source_record']['position_m'] for o in raw)
    if not preserved:raise RuntimeError('stable source identities')
    save(evidence/'identities.json',dict(passed=True,original_source_objects=len(raw),source_ids=sorted(o['id'] for o in raw),world_id=snapshot['compatibility']['world_id'],layout_version=snapshot['compatibility']['layout_version'],graph_version=snapshot['compatibility']['graph_version'],schema_passed=True,packages=packages))
    run(evidence,'repository',[sys.executable,'verify_repository.py'])
    run(evidence,'plugin_source',[sys.executable,'plugin-source/verify_source.py'])
    run(evidence,'sealed_protection',[sys.executable,'tools/verify_review_protection.py'])
    shutil.copyfile(ROOT/'review-work/protection.json',evidence/'sealed_protection_result.json')
    run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise RuntimeError(scope['errors'])
    archive=work/(a.build_id+'_windows.zip')
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted((work/'CLEAN_WINDOWS').iterdir()):bundle.write(path,path.name)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:raise RuntimeError('zip CRC')
    save(evidence/'archive.json',dict(path=str(archive),sha256=sha(archive),bytes=archive.stat().st_size,crc_passed=True))
    extra=[*(ROOT/'tools/map_v02').glob('e2_*.py'),ROOT/'docs/map_v02/E2_IMPLEMENTATION.md',ROOT/'schemas/map_v02/presentation_package.schema.json']
    save(evidence/'supplemental_sources.json',dict(files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in sorted(extra)]))
    camera=next(row for row in native['observations'] if 'native_camera_before' in row)
    b=camera['native_camera_before'];c=camera['native_camera_after']
    counters=[('源快照读取',b['planner']['planner']['snapshot_reads'],c['planner']['planner']['snapshot_reads']),('完整索引建立',b['planner']['index']['full_index_builds'],c['planner']['index']['full_index_builds']),('可见排序',b['planner']['planner']['sort_calls'],c['planner']['planner']['sort_calls']),('对象绘制命令重建',b['renderer']['object_draw_callbacks'],c['renderer']['object_draw_callbacks'])]
    text=f'''# 潼关 v0.2：E2 可见查询与绘制计划缓存

构建 `{a.build_id}`。本批完成反向空间桶、可见查询、修订失效、稳定排序、Godot绘制命令复用及实际提交审计。E1加载器和包协议继续共用；没有覆盖旧地图、旧素材或已封存S0/V1/E1交付。

## 启动与复现

启动 `H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/CLEAN_WINDOWS/Start-E2.cmd`。按1看4×4工程夹具、2看原潼关有效快照、3看四桶巨树且owner块在视口外的反例；R切全量参考、G切页界，拖动/滚轮移动缩放，Esc退出。

可重新导入的独立Godot工程：`review-work/map_v02/{a.build_id}/SOURCE_RUNTIME/project.godot`。原工程默认入口仍保持原样。源码入口位于runtime/v02/e2；需要由e2_build.py生成分页包与配置后运行。

Windows zip和CRC/SHA在evidence/archive.json。干净运行目录只有exe/pck/cmd，全部JSON/导入纹理由导出PCK提供。未依赖原工程或编辑器缓存，未同时初始化旧六块地形缓存。

## 实现与缓存边界

- 512m桶使用floor和半开边界。每个对象只有一份只读派生记录，桶只引用稳定ID；完整paint矩形负责跨桶依赖与可见剔除，owner和ground/protection保留原含义。矩形剔除不宣称为任意多边形精确相交。
- 查询只访问视口桶、合并去重候选、对候选检查paint矩形，不在查询中枚举全量对象。跨页树冠保留owner payload分片依赖；实际工程巨树在owner块完全离屏时仍只提交一次。
- world/build、有效制作修订、资产范围版本与索引参数共同识别缓存。源提供器只在修订变化时调用；新增、删除、移动与资产变大只重建受影响对象的桶。相同可见版本集复用排序结果，排序键为(render_plane,ground_depth,stable_id)。
- 渲染使用持久CanvasItem命令；同一可见计划下平移/缩放只更新根变换，不重新调用对象_draw。必要时先减局部绘制原点再构造Vector2。显示修订、LOD键或相关对象内容变化使可见计划失效；语义LOD和资源淡化本身尚未实施。
- draw前审计实际(entity_id,representation_id)提交，重复同表示拒绝；受控过渡配对最多两种表示。后者仅实现审计约束测试，并非完成E3淡化。已烘焙表示不重复提交为动态地物。

## 同可见量的查询证据

| 元数据总数 | 可见对象 | 桶候选 | 本次精确检查 | 查询全量枚举 |
|---:|---:|---:|---:|---:|
'''
    for row in matrix:text+=f"| {row['total_objects']} | {row['visible']} | {row['candidates']} | {row['query_candidate_tests']} | {row['query_full_record_enumerations']} |\n"
    text+='''
每档另执行独立Rect2全量参考并比对ID和顺序，参考枚举计数均由0变为1，作为计数器正向对照。构造/索引/参考总耗时保留在原始JSON，不能当作单次查询延迟、游戏FPS或城市容量。没有用永远不更新的“全量plan=0”字段冒充测量；使用实际快照调用、源记录校验、桶候选访问、排序和CanvasItem回调计数。

## 原生相机与修订证据

连续40次小幅平移，保持相同可见集，实测：

| 事件 | 移动前 | 移动后 |
|---|---:|---:|
'''
    for label,left,right in counters:text+=f'| {label} | {left} | {right} |\n'
    text+=f'''
工程夹具、潼关、四桶巨树三机位，以及运行时移走对象、恢复后把素材显示宽度从800m改为1600m的工程反例，均逐像素等于同镜头全量源记录交给GPU裁剪的参考。比较范围是实际1920×1080图中的1600×940地图区；UI计数区不混入像素比较。所有十张原始截图保留，没有后期修改。

运行时移动只重建一个对象的桶，旧可见绘制命令清除；放大素材后完整paint范围与桶更新，原ID及接地点保持不变。此修改只存在测试进程的工程元数据内，不写包、旧地图或源PNG，不授权实际制作端放置巨树。

正常CanvasItem提交ID及顺序与可见计划相同。另向真实渲染器注入一次重复记录，实际submit审计返回duplicate_representation且不重复绘制；恢复输入后重新验证干净帧。审计计数指脚本发出的CanvasItem绘制命令，不当作驱动批次/GPU draw-call或GPU帧计数。

## 检查、身份与保护

- 当前源码契约：{read(boundary/'final_source_core.json')['checks']}项通过，包含原共享GameState读取前后不变。
- 独立工程核心与包回归：{source['checks']}项通过；Windows Release：{native['checks']}项通过，诊断为空，其中包含未修改E1检查的回归。
- 重复原始ID、字典key/record.id不符、错误owner、非法delta整批拒绝、负坐标/半开边界、四桶去重、旧空桶重建、素材增大/缩小/过期版本、显示修订、世界/build切换、固定排序、烘焙重复及受控表示配对均已验证。
- 原占地、发布、实例身份、通道、建设、存档、E1适配器回归通过，命令/退出码/输出在evidence/regressions_final.json。
- 潼关仍为原72个有效实例，加原关楼/道路表现；ID、位置、手工新增/删除/固定、八地块、v4/Save22、通道与生成器身份保留。工程巨树仅加入新的stream_lab_v02夹具，不是第二个历史节点或新绘制美术。
- 开工前{len(before)}个已有文件逐一哈希不变；旧封存发行、仓库白名单、插件空素材库及空白检查通过。未提交、推送或发布。

## 失败记录、范围与回退

开发期修正了reference命名与RefCounted既有方法冲突，以及依赖脚本中Variant条件的Bool推断问题。一次依赖编译失败导致测试流程未立即完成，仅终止了命令行含该次独有report路径的自有Godot进程；失败日志保留在evidence/development，未关闭用户编辑器或其它运行包。最终测试由超时守卫、退出码和ERROR/WARNING/泄漏诊断共同判定，不能只看failures数组。

01/02开发构建保留在review-work，不替代最终03。后续补充了运行时修订的真实像素验证，并将早期常零的全量计数字段换为带正向对照的实际枚举/访问计数，原证据未覆盖。

本批新入口继续是只读制作表现与工程验证，尚未把E2接入旧默认玩法入口；正式两线整合按文档留给C1。E1资源仍同步读取和驻留，地形页/地点代理暂未做本批之外的流式筛选。E3加载状态机、预算、异步epoch、真实释放/重载，V2完整玩法画面和Q1总验收均不在本批完成声明。没有新增p95/p99、显存预算或全国容量通过结论。

回退只需关闭E2，继续启动原E1、V1或S0包，无旧地图、素材、注册表或存档迁移。

[查询矩阵](QUERY_MATRIX.json) · [原生像素/修订/提交证据](NATIVE_COMPARISONS.json) · [源码清单](evidence/SOURCE_MANIFEST.json) · [保护检查](evidence/protection.json)
'''
    (report/'REPORT.md').write_text(text,encoding='utf-8')
    save(report/'ACCEPTANCE.json',dict(stage='E2',build_id=a.build_id,source='passed',native='passed',query='passed',draw_plan_cache='passed',old_files_unchanged=True,e1_regression='passed',visual='render_equivalence_only_no_new_art',history='not_claimed',capacity='metadata_correctness_only',e3='not_implemented',c1='not_implemented',q1='not_complete'))
    save(report/'DELIVERY_MANIFEST.json',dict(build_id=a.build_id,files=[dict(path=p.relative_to(report).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in source_files(report) if p.name!='DELIVERY_MANIFEST.json']))
    print('E2_READY',report,flush=True)


if __name__=='__main__':main()
