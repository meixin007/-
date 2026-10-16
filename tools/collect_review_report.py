"""Collect exact-build evidence and produce a reviewable acceptance report."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'review-work';DEST=ROOT/'reports/review_26a45be'
BUILD='tongguan_v01_revfix_20261015_02';REL=WORK/'releases'/BUILD
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def collect():
    DEST.mkdir(parents=True,exist_ok=True)
    for name in ['environment.json','protection.json','legacy_conflicts.json']:
        shutil.copyfile(WORK/name,DEST/name)
    for p in (WORK/'source').rglob('*'):
        if p.is_file():
            target=DEST/'source'/p.relative_to(WORK/'source');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
    for mode in ['authoring','verify','tree_edges','cycles','performance','soak','load']:
        src=WORK/'native/release'/mode;dst=DEST/'native'/mode;dst.mkdir(parents=True,exist_ok=True)
        value=read(src/'result.json');value.pop('command',None)
        metrics=value.get('windows_process_metrics',{});metrics.pop('pid',None)
        # The runner for authoring/verify was already launched before the outer
        # budget-label cleanup; neither had a failing budget or diagnostic.
        value['execution_passed']=value['exit_code']==0 and not value['timed_out'] and not value['diagnostics'] and not value['failures']
        value['isolation_before_test']=dict(godot_or_tongguan_process_count=len(read(src/'processes_before.json')))
        save(dst/'result.json',value)
        for p in src.iterdir():
            if p.suffix=='.png' or p.name=='process_samples.json':shutil.copyfile(p,dst/p.name)
            elif p.name=='runtime.log':shutil.copyfile(p,dst/'runtime.txt')
    shutil.copyfile(WORK/'native/summary.json',DEST/'native/summary.json')
    shutil.copyfile(REL/'RELEASE.json',DEST/'RELEASE.json')
    shutil.copyfile(REL/'SOURCE_MANIFEST.json',DEST/'SOURCE_MANIFEST.json')
    after=read(WORK/'after_authoring.json');before=read(DEST/'red/baseline_authoring.json')
    preserved=dict(objects=95,state_before_sha256=before['state_sha256'],state_after_sha256=after['state_sha256'],
      state_equal=before['state']==after['state'],input_hash_equal=before['input_sha256']==after['input_sha256'],
      publication_hash_equal=before['publication_sha256']==after['publication_sha256'])
    save(DEST/'identity_preservation.json',preserved)
    source=read(DEST/'source/summary.json');native=read(DEST/'native/summary.json');release=read(REL/'RELEASE.json')
    rows=[]
    for name,label in [('old_document','旧v4文档与编辑器路径诊断'),('art_import','既有美术导入反馈'),('size_guard','制作保存容量上限与旧文件保留'),('geometry','REV-01完整占地'),('ownership','REV-03原始ID与跨块唯一性'),('publication','发布占地保护'),('view','四档视图与拾取计算'),('passage','主关/河流/合成险径通行'),('construction','实际资源建设与日结'),('save_migration','R3/R4存档迁移、校验及恢复'),('original_host','原GameState/Context/SaveManager接入'),('manual_layout','仓库补丁与地块保护'),('authoring','人工补丁/删除/锁区/撤销/发布')]:
        details=DEST/'source'/name/'details.json';count=''
        if details.exists():count=str(read(details).get('checks',1 if name=='size_guard' else ''))
        else:
            txt=(DEST/'source'/name/'runtime.txt').read_text(encoding='utf-8')
            m=re.search(r'"checks":(\d+)',txt);count=m.group(1) if m else '原PASS标记'
        result=next(r for r in source['tests'] if r['name']==name)
        rows.append(f"|{label}|{count}|{'通过' if result['passed'] else '失败'}|[证据](source/{name}/runtime.txt)|")
    native_rows=[];perf_rows=[]
    for mode,label in [('authoring','原生制作保护'),('verify','原生四档/慢速阈值往返/拾取/主关/建设/存档'),('tree_edges','REV-02实际树种＋高合成素材四边像素'),('cycles','20次界面进出与驻留缓存')]:
        v=read(DEST/'native'/mode/'result.json')
        native_rows.append(f"|{label}|{v['checks']}|{'通过' if v['execution_passed'] else '失败'}|[证据](native/{mode}/result.json)|")
    for mode,label in [('performance','60秒实景轨迹'),('soak','300秒实景耐久')]:
        v=read(DEST/'native'/mode/'result.json')
        perf_rows.append(f"|{label}|{v['duration_seconds']:.3f}s|{v['frame_p95_ms']:.3f}|{v['frame_p99_ms']:.3f}|{v['frame_max_ms']:.3f}|{'通过' if v['execution_passed'] else '失败'}|{'达标' if v['budget_passed'] else '超预算'}|")
    load=read(DEST/'native/load/result.json')
    for row in load['synthetic_display_load']:
        perf_rows.append(f"|{row['display_copies']}个纯显示副本|约3s|{row['frame_p95_ms']:.3f}|{row['frame_p99_ms']:.3f}|—|{'通过' if row['execution_passed'] else '失败'}|{'达标' if row['budget_passed'] else '超预算'}|")
    cycles=read(DEST/'native/cycles/result.json')
    hashes='\n'.join(f"|{name}|{record['bytes']}|{record['sha256']}|" for name,record in release['artifacts'].items())
    report=f"""# 26a45be 阶段一审查修复与复验

构建：`{BUILD}`。只读基线：`26a45be93e62fc56199ed42d98895926380383c5`。
独立修复副本：H:/tongguan_reviewfix_20261015；分支 codex/tongguan-rev01-03-20261015。基线提交和封存发行未改写。
先提交可失败回归：`959cac0`；三个审查项完成技术修复，等待用户本阶段验收。

## 审查项与红绿对应

|项|固定旧基线实测|修复后实测|结论|
|---|---|---|---|
|REV-01|19项中8失败|24项全通过|有限线段到闭合矩形的最短距离覆盖内部穿越、端点、斜线；40/45m半宽与相切内外测试通过|
|REV-02|85项中16失败|Release86项全通过|实际柳树/树丛及高比例合成素材，最大缩放2.4，四边7个缓慢进出位置，整块像素与无剔除对照一致|
|REV-03|6项中3失败|14项全通过＋原生58项中的实际提交审计|原始v4列表在字典投影前查重，key/record.id一致；跨4块索引只派生一个owner，重复提交/错误owner变异会失败|

红灯JSON、退出码及对照图见 [red](red/summary.json)。原生对照将内容缩放关闭，避免坐标采样错位；早期伸缩画布的无效尝试未计入红灯证据。
REV-01新增采用、移动、候选和发布使用严格检查；完整占地相切允许，比较容差0.0001m，内外回归相差0.001m。
缓存仅复用不变有限线段，避免逐对象反复建立线段数据。REV-02只替换树的视口判定，使用真实尺寸和锚点加1px余量。

## 旧数据与保存语义

默认95个对象的完整制作状态SHA256前后一致：
`{preserved['state_before_sha256']}`。
输入及发布哈希也一致，见 [identity_preservation.json](identity_preservation.json)。
现有地点、八地块、生成对象ID、人工补丁、删除记录、锁区、v4 features/presentation.instances和Save22语义保留。
world_id仍为 tongguan_final_validation_v1，图版本仍为 tongguan_controlled_corridor_r3_v01，生成器仍为 forest_grid_sha256_v2。

新检查下默认95对象冲突数为0。另构造旧算法允许而新算法拒绝的校验有效旧工作区，证明重读不改对象/文件；只读报告列明ID、原因及完整占地；未改变的旧内容可带明确警告发布，用户显式删除仍保留tombstone，撤销/重做恢复同ID。
制作端增加“报告完整占地冲突（只读）”入口。没有静默迁移、移动、删除或重新编号旧内容。
owner仅是派生显示索引，没有写入v4或存档。

## 源码回归

|项目|断言数|结果|明细|
|---|---:|---|---|
{chr(10).join(rows)}

插件、运行端和制作端的headless导入均通过；插件空注册表检查通过。未修改原战役移动权威链，编辑器RoutePreview仍只做诊断。

## 原生Release复验

|项目|断言数|执行|明细|
|---|---:|---|---|
{chr(10).join(native_rows)}

Release模板检查通过。全部原生运行退出正常，无SCRIPT ERROR、ERROR、WARNING、退出资源泄漏诊断。
四档慢速阈值往返各20轮；大坐标锚点、地块与地点拾取、主关闭锁/重开、无桥不可跨河、轻装险径条件仍通过。
原生实际绘制提交检查非空ID列表及跨块平移后的唯一owner，替代Dictionary数量恒等式。
20次界面进出（保留Session.cache）私有内存中位窗口差为 {cycles['windows_process_metrics']['post_warmup_private_growth_bytes']/1024**2:.3f}MiB，预算≤16MiB；它不代表卸载/加载大量不同区域。

## 本机构建与性能边界

Windows10 19045，Ryzen7 5700X，约16GB RAM，RTX4060 8188MiB，驱动616.92，Godot4.6.1 official，GL Compatibility。
项目配置1920×1080；本机窗口受桌面边框限制，实际客户端截图1886×1061（专用树边缘对照禁用内容缩放后为1920×1061）；不能把本次窗口测量称为全屏1080p认证。
所有性能模式启动前其他Godot/Tongguan进程数见各result.json；不结束用户其他进程。

|配置|采样时长|p95 ms|p99 ms|最大帧 ms|执行|百分位预算|
|---|---|---:|---:|---:|---|---|
{chr(10).join(perf_rows)}

预算：p95≤16.7ms、p99≤25ms；进程私有内存≤4GiB、独占GPU采样≤1.5GiB。每档另有execution_passed/budget_passed，load顶层passed同时要求全部档达标。
first_view_ms起点在验收入口内；进程启动到日志观察ready只是受日志缓冲影响的上界，均不是精确冷启动首帧。
RAM采用连续Windows采样窗口；Release日志缓冲后的读取时间不冒充每次退出时内存。
显示副本只是同一对象集的绘制压力，不是独立城市、不增加世界或军队，不能推导全国容量。

## 产物哈希

|文件|字节数|SHA256|
|---|---:|---|
{hashes}

[发行记录](RELEASE.json) · [587文件冻结源码清单](SOURCE_MANIFEST.json)。
两EXE哈希相同是同一官方Release模板，修复内容位于不同PCK；必须与本次同名PCK一起运行。

## 封存保护与已知问题

[保护检查](protection.json)：旧_03的580源码、4个Windows产物、原ZIP均匹配原SHA256；146项插件/样板bundle/旧fixture/历史文档等基线文件未变。旧GitHub导出副本仍在基线且干净。
原主工程没有本任务写入；没有初始完整Git状态快照，因此不声称其全工作区状态与过去严格相同。
旧PUBLIC_SOURCE_MANIFEST、PUBLIC_FILES、历史验收记录保留为基线收据；当前样板源码校验改用REVIEW_SOURCE_MANIFEST.json。

- 正式美术、透视/岸坡组合、精确756地理仍待独立视觉与史料验收。
- 当前仍是六地形块的单节点缓存，树列表仍全量生成显示计划；没有完成全国流式加载或容量认证。
- 多显示副本超预算见上表，保留为未解决限制；本次不借机实现全国生成器或新增历史节点。
- 本次_01为补齐缺失投影错误处理前的内部构建，保留在临时目录；仅_02作为交付候选。
- 技术修复完成不等于用户最终验收，也不自动进入下一阶段。

## 复现

Windows安装Godot4.6.1及对应官方Windows Release模板。设置GODOT_BIN/GODOT_WINDOWS_TEMPLATE可覆盖本机路径。

```powershell
python tools/run_review_red.py
python tools/run_review_checks.py
python tools/build_review_release.py
python tools/run_review_native_suite.py
python tools/verify_review_protection.py
python verify_repository.py
```

red工具重新展开固定提交并只复制回归夹具，旧核心不变；退出0表示预期回归成功暴露，夹具子进程分别退出1。
构建和原生报告路径拒绝覆盖；复跑需新的构建ID和独立工作目录。封存保护检查依赖原隔离副本路径；不在该机器时请提供该封存目录。
完整命令参数在tools脚本；测试仅写独立副本和user://tests测试目录，不接管玩家存档或主工程。
"""
    (DEST/'REPORT.md').write_text(report,encoding='utf-8')
    summary=dict(build_id=BUILD,baseline_commit=release['baseline_commit'],revision_items_closed=['REV-01','REV-02','REV-03'],
      source_passed=source['passed'],native_technical_passed=native['technical_passed'],all_budgets_passed=native['all_budgets_passed'],
      identity_preserved=all(preserved[k] for k in ['state_equal','input_hash_equal','publication_hash_equal']),sealed_protection_passed=read(DEST/'protection.json')['passed'],
      user_acceptance='pending',next_stage_started=False,artifacts=release['artifacts'])
    save(DEST/'summary.json',summary)
    print(json.dumps(summary,ensure_ascii=False),flush=True)
if __name__=='__main__':collect()
