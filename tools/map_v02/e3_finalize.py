"""Seal final E3 evidence and preserve earlier files/deliveries byte for byte."""
import argparse,re,shutil,sys,zipfile
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from e1_compile import validate_package
from v1_finalize import run

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;report=ROOT/'reports/map_v02'/a.build_id
    report.mkdir(parents=True,exist_ok=False);evidence=report/'evidence';evidence.mkdir()
    native=read(work/'native_01/result.json')
    if not native['technical_passed']:raise RuntimeError('native not passed')
    for row in read(work/'SOURCE_MANIFEST.json')['files']:
        if sha(ROOT/row['path'])!=row['sha256']:raise RuntimeError('source changed '+row['path'])
    for path in source_files(RUNTIME/'v02/e3'):
        if path.suffix in {'.gd','.tscn'} and sha(path)!=sha(work/'SOURCE_RUNTIME/v02/e3'/path.name):raise RuntimeError('stage mismatch '+path.name)
    for name,row in read(work/'ARTIFACTS.json').items():
        if sha(work/'CLEAN_WINDOWS'/name)!=row['sha256']:raise RuntimeError('artifact changed')
        if name in native['artifacts'] and native['artifacts'][name]!=row['sha256']:raise RuntimeError('tested artifact mismatch')
    for name in ['SOURCE_MANIFEST.json','ARTIFACTS.json','PROFILES.json','effective_snapshot.json','snapshot.txt','snapshot_run.json','scope.json','export.json','export.txt','import.json','import.txt','import_pixels.json','import_pixels.txt']:
        shutil.copyfile(work/name,evidence/name)
    shutil.copytree(work/'native_01',report/'native',ignore=shutil.ignore_patterns('*.log'))
    boundary=ROOT/'review-work/map_v02/e3_boundary';shutil.copytree(boundary,evidence/'development')
    regressions=ROOT/'review-work/map_v02/e3_regressions';shutil.copytree(regressions,evidence/'regressions')
    if not read(regressions/'final_summary.json')['passed']:raise RuntimeError('regression not passed')
    before=read(boundary/'before.json')['files'];changed=[r['path'] for r in before if not (ROOT/r['path']).is_file() or sha(ROOT/r['path'])!=r['sha256']]
    save(evidence/'protection.json',dict(passed=not changed,files=len(before),changed=changed))
    if changed:raise RuntimeError('old files changed')
    packages=[]
    for key in ['stream','lab','tongguan']:
        folder=work/'SOURCE_RUNTIME/v02/e1/packages'/key;m=read(folder/'presentation.package.json');validate_package(folder,m['compatibility'])
        for path in folder.rglob('*.json'):
            target=evidence/'packages'/key/path.relative_to(folder);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
        packages.append(dict(name=key,manifest_sha256=sha(folder/'presentation.package.json'),pages=len(read(folder/'world.catalog.json')['pages'])))
    snapshot=read(work/'effective_snapshot.json');objects=read(work/'SOURCE_RUNTIME/v02/e1/packages/tongguan/instances/objects.json')['objects']
    raw=[o for o in objects if o.get('source_record')]
    if sorted(o['id'] for o in raw)!=sorted(snapshot['raw_instance_ids']) or any(o['id']!=o['source_record']['id'] or o['position_m']!=o['source_record']['position_m'] for o in raw):raise RuntimeError('source identities')
    save(evidence/'identities.json',dict(passed=True,original_objects=len(raw),source_ids=sorted(o['id'] for o in raw),packages=packages))
    dev=[]
    for build in ['tongguan_v02_e3_20261016_01','tongguan_v02_e3_20261016_03']:
        path=ROOT/'review-work/map_v02'/build/'native_01/result.json';value=read(path)
        dev.append(dict(build_id=build,path=str(path),sha256=sha(path),checks=value['checks'],technical_passed=value['technical_passed'],failures=value['failures'],diagnostics=value['diagnostics']))
    save(evidence/'prior_native_runs.json',dict(runs=dev,untested_build='tongguan_v02_e3_20261016_02 staging only; superseded before native run'))
    run(evidence,'repository',[sys.executable,'verify_repository.py'])
    run(evidence,'plugin_source',[sys.executable,'plugin-source/verify_source.py'])
    run(evidence,'sealed_protection',[sys.executable,'tools/verify_review_protection.py'])
    shutil.copyfile(ROOT/'review-work/protection.json',evidence/'sealed_protection_result.json')
    run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise RuntimeError(scope['errors'])
    archive=work/(a.build_id+'_windows.zip')
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
        for path in sorted((work/'CLEAN_WINDOWS').iterdir()):z.write(path,path.name)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise RuntimeError('zip CRC')
    save(evidence/'archive.json',dict(path=str(archive),sha256=sha(archive),bytes=archive.stat().st_size,crc_passed=True))
    extras=[*(ROOT/'tools/map_v02').glob('e3_*.py'),ROOT/'docs/map_v02/E3_IMPLEMENTATION.md',RUNTIME/'tests/v02/test_e3_lifecycle.gd']
    save(evidence/'supplemental_sources.json',dict(files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in sorted(extras)]))
    stream=next(r for r in native['observations'] if r['case']=='20_round_native_stream')
    control=next(r for r in native['observations'] if r['case']=='retained_command_positive_control')
    s=stream['telemetry']['residency']['stats'];first=stream['windows'][0];last=stream['windows'][-1]
    summary=dict(build_id=a.build_id,checks=native['checks'],rounds=len(stream['windows']),unique_total_bytes=stream['unique_total_bytes'],unique_visited_bytes=stream['unique_visited_bytes'],visited_textures=stream['unique_visited_textures'],profile=native['profiles']['stream'],stream_stats=s,first_window=first,last_window=last,all_windows=stream['windows'],reference_control=control,backend=native['backend'],private_bytes_peak=native['private_bytes_peak'],verified_import_pixels=len(native['verified_import_pixels']),max_adopt_plus_commands_usec=max(f.get('adopt_plus_plan_usec',0) for f in stream['frames']),gpu_actual_bytes=None,frame_performance_acceptance='not_run_Q1')
    save(report/'LIFECYCLE_SUMMARY.json',summary)
    text=f'''# 潼关 v0.2 E3：加载状态机、预算与释放／重载

最终构建 `{a.build_id}`，父提交仍为62546a547895e1a6185904ad60bf15fa58c03244。E3源代码、干净Windows包与本报告绑定同一清单；本批仅新增E3及测试、构建和文档，不覆盖既有地图、素材、S0/V1/E1/E2代码或发行。

## 启动

`H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/CLEAN_WINDOWS/Start-E3.cmd`

1为256细页工程世界，2为4×4边界／缺页夹具，3为实际潼关。三者共用同一MapService、ResidencyManager及原E1包验证器／E2对象查询。N跳往下一片区域，C完整释放后重载，B切低／默认预算，拖动／滚轮，Esc或窗口关闭时排空自有请求再退出。

独立可编辑工程为同构建目录的SOURCE_RUNTIME/project.godot。新入口不初始化旧六块地形缓存；原默认玩法入口不变，C1整合后续执行。回退只需关闭E3并启动旧包，无地图、素材或存档迁移。

## 实现

- 实际异步状态流UNLOADED→QUEUED→LOADING→READY_CPU→ATTACHING→RESIDENT及FAILED／EVICT_PENDING。只在LOADED后get，排队可撤销、已开始任务继续跟踪并安全排空。world/build epoch阻止旧包挂入；相机移动不增长全局epoch。相同路径／哈希由当前有效消费者明确认领。
- 页面桶、覆盖树与E2对象可见集求需求；根底图优先于中间父页、可见细节和至多4个预取页。大视野选粗层。稀疏详细区之外仍保留低清覆盖；缺页失败和父页成功分别记录，版本不兼容拒绝混接。
- 唯一纹理RGBA8估算含gutter，遵守E1 base-only/no-mip/lossless契约。resident+在途/READY预留受硬预算限制，解码预留单列，最多2个实际在途请求。父子淡化双持有计入；预算降低先清预取和旧页、再细节／中间父页，保留可负担根底图。已开始预留不可物理取消，缩预算时停止准入并排空，账本保留暂时超额。
- get/采用/验证实测合用2ms调度目标，绘制计划构建使用当帧剩余额度，单操作不可抢占；超额记录并推迟后续工作。实际纹理pixel_sha256读回单列在测试稳定帧执行，不计入生产挂接或正式性能采样。生产根据封存导入身份、请求源哈希和实际尺寸校验。
- 淘汰回调先清CanvasItem命令、节点Texture2D引用，再移除资源表强引用；共享图集最后消费者离开才释放。WeakRef实际失效转为带对象instance_id的事件后丢弃，交互历史有界；验收模式另保留完整日志。

## 原生生命周期结果

Windows Release实际1920×1080，{native['checks']}项检查通过，退出码0、超时false、ERROR/WARNING/资源泄漏诊断为空。包含E1原生回归及E2完整元数据契约，另有当前源码E3与原占地、owner、发布、通道、建设、存档回归。测试数量是各作用域结果，不能相加为城市容量。

压力profile在构建／执行前冻结为软4MiB、硬8MiB、解码4MiB、并发2、挂接2ms、宽限0；正常profile仍为256/320MiB、解码64MiB、宽限2秒。未调高阈值以通过测试。

| 证据 | 实测 |
|---|---:|
| 唯一工程纹理 | 261张：256细页＋4父页＋1根页 |
| 工程总RGBA8估算 | {stream['unique_total_bytes']/1048576:.4f} MiB |
| 20轮实际访问不同细页 | {stream['unique_visited_textures']}张／{stream['unique_visited_bytes']/1048576:.4f} MiB |
| 实际请求／采用 | {s['requests']}／{s['attaches']} |
| 驻留释放／实际WeakRef失效 | {s['drops']}／{s['released_observed']} |
| 重新资源请求 | {s['reloads']} |
| 最大并发 | {s['peak_inflight']} |
| 压力路线最大get/采用时间 | {s['max_attach_usec']/1000:.3f} ms |
| 压力路线采用＋命令计划最大值 | {summary['max_adopt_plus_commands_usec']/1000:.3f} ms |
| 压力路线2ms采用超额 | {s['attach_overruns']} |
| 第1轮／第20轮同视野驻留 | {first['accounting']['resident']}／{last['accounting']['resident']} bytes |
| 第1轮／第20轮引擎Resource计数 | {int(first['engine_resources'])}／{int(last['engine_resources'])} |
| 第1轮／第20轮已退役纹理仍存活 | {first['retired_weak_alive']}／{last['retired_weak_alive']} |

路线64个机位在同一8×32世界中覆盖四条分隔行，20轮均以相同机位和稳定期采窗。实际访问量{stream['unique_visited_bytes']/native['profiles']['stream']['soft']:.2f}倍软预算；每页request、attach、last_reference_drop、released_observed和reload见native/result.json。固定profile每帧resident+reserve、解码预留均通过；同视野纹理引用、引擎Resource及驻留字节无增长。首次机位返回后与初次地图区逐像素相等，实际潼关完整释放／重载前后亦逐像素相等。

实际读回验证{len(native['verified_import_pixels'])}个导入纹理身份，截图保留在native/。截图与读回不属于正式p95/p99采样。

## 故障与反向对照

真实缺失细页保留FAILED，兼容父页实际就绪；错误哈希拒绝且可显式重试；真实在途任务延迟用于A→B→A及包切换；旧包完成被取回释放而不挂入新包；旧父页build不匹配被识别；根／父未就绪明确pending；共享图集先两消费者、再一个、最后全部释放；淡化中缩到一张根页预算后根页仍绘制。

故意断开淘汰回调、暂停自动重绘并只清自有缓存，检测到{control['retained_alive']}个真实绘制引用仍存活；随后清CanvasItem命令和节点纹理，存活变为{control['after_clear_alive']}。该负面对照证明检查能发现“删字典但没有释放”，并非只观察程序未崩溃。

## 保护、过程与限制

开工前保护清单{len(before)}个已有文件哈希全部不变，旧地图／素材、已有v4和Save22、72实例ID/位置、补丁、删除、固定及通道保持。仓库范围、空素材插件、旧封存保护和空白检查通过；未提交、推送、发布。实际潼关与工程夹具只读表现，无新GameState、军队或经济服务。

开发构建01保留了根底图与中间父页同优先级的错误；已修为分级降级，并补充未对齐粗页跨桶查询。两项测试脚手架问题也保留：初次／返回相机缩放不同，以及自动重绘提前清除了负面对照应保留的引用；已统一镜头、仅在反向对照暂停自动重绘。初轮存档回归缺少既有TONGGUAN_R5_FIXTURES环境变量，补入原夹具目录后32项通过；首次失败未覆盖。03通过451项，但04补齐get/命令构建计时和额外故障验证，只有04为本交付；02只构建未原生验收。

观测到的自有进程PrivateUsage峰值{native['private_bytes_peak']/1048576:.2f}MiB，包含100k元数据测试、完整日志及引擎分配池；不是地图纹理预算或独占显存。引擎纹理监视器涵盖字体/UI，释放对象与RSS/驱动池下降不能等同。独占GPU内存为null。2ms测量是该工程路线的调度数据，不是端到端帧时或卡顿保证。

本批不签署Q1的3×60s+300s正常p95/p99矩阵、全国容量、V2完整美术/玩法、C1正式入口／离屏施工接线或历史复原。数值256px工程页并非新增手绘资源量产，也不替代1024px正式页的视觉审核。E3源/原生/生命周期技术通过不替代作者美术审阅。

[生命周期汇总](LIFECYCLE_SUMMARY.json) · [完整原生日志](native/result.json) · [保护检查](evidence/protection.json) · [回归及存档重试](evidence/regressions/final_summary.json) · [构建源清单](evidence/SOURCE_MANIFEST.json)
'''
    (report/'REPORT.md').write_text(text,encoding='utf-8')
    save(report/'ACCEPTANCE.json',dict(stage='E3',build_id=a.build_id,source='passed',native='passed',lifecycle='passed',budget='fixed_profile_admission_and_scheduling_passed',references='actual_release_reload_passed',old_files_unchanged=True,visual='reload_pixel_equivalence_only',gpu_dedicated_budget='not_measured',q1_frame_time='not_run',c1='not_implemented',v2='not_claimed',history='not_claimed',capacity='engineering_fixture_only'))
    save(report/'DELIVERY_MANIFEST.json',dict(build_id=a.build_id,files=[dict(path=p.relative_to(report).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in source_files(report) if p.name!='DELIVERY_MANIFEST.json']))
    print('E3_READY',report,flush=True)

if __name__=='__main__':main()
