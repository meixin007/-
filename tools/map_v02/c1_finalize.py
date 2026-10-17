"""Seal C1 functional evidence; visual/history/Q1 gates remain explicit."""
import argparse,re,shutil,sys,zipfile
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_finalize import run

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;native=read(work/'native_01/result.json');reg=ROOT/'review-work/map_v02/c1_regressions'
    if not native['technical_passed'] or not read(reg/'summary.json')['passed']:raise RuntimeError('validation incomplete')
    report=ROOT/'reports/map_v02'/a.build_id;report.mkdir(parents=True,exist_ok=False);evidence=report/'evidence';evidence.mkdir()
    manifest=read(work/'SOURCE_MANIFEST.json')
    for row in manifest['files']:
        file=ROOT/row['path']
        if sha(file)!=row['sha256']:raise RuntimeError('source changed '+row['path'])
        if file.is_relative_to(RUNTIME) and sha(work/'SOURCE_RUNTIME'/file.relative_to(RUNTIME))!=row['sha256']:raise RuntimeError('stage changed '+row['path'])
    for name,row in read(work/'ARTIFACTS.json').items():
        if sha(work/'CLEAN_WINDOWS'/name)!=row['sha256'] or name in native['artifacts'] and row['sha256']!=native['artifacts'][name]:raise RuntimeError('tested artifacts changed')
    before=read(ROOT/'review-work/map_v02/c1_boundary/before.json')['files']
    changed=[r['path'] for r in before if not (ROOT/r['path']).is_file() or sha(ROOT/r['path'])!=r['sha256']]
    save(evidence/'protection.json',dict(passed=not changed,files=len(before),changed=changed))
    if changed:raise RuntimeError('pre-existing files changed')
    # Record the reused runtime source chain, independently of the C1 delta manifest.
    reused=[]
    for row in before:
        file=ROOT/row['path']
        if not file.is_relative_to(RUNTIME) or file.name in {'project.godot','export_presets.cfg'}:continue
        staged=work/'SOURCE_RUNTIME'/file.relative_to(RUNTIME)
        if sha(staged)!=row['sha256']:raise RuntimeError('reused runtime mismatch '+row['path'])
        reused.append(row)
    save(evidence/'reused_runtime.json',dict(passed=True,files=reused))
    shutil.copytree(work/'native_01',report/'native',ignore=shutil.ignore_patterns('*.log'))
    shutil.copytree(reg,evidence/'regressions')
    for name in ['SOURCE_MANIFEST.json','ARTIFACTS.json','PROFILES.json','snapshot_run.json','snapshot.txt','import.json','import.txt','import_pixels.json','import_pixels.txt','export.json','export.txt']:shutil.copyfile(work/name,evidence/name)
    development=evidence/'development';development.mkdir()
    for name in ['red.txt','policy_green.txt']:shutil.copyfile(ROOT/'review-work/map_v02/c1_boundary'/name,development/name)
    for build in ['tongguan_v02_c1_20261016_01','tongguan_v02_c1_20261016_02','tongguan_v02_c1_20261016_03']:
        for name in ['result.json','runtime.txt']:
            source=ROOT/'review-work/map_v02'/build/'native_01'/name
            if source.exists():shutil.copyfile(source,development/(build+'_'+name))
    save(development/'RCA.json',dict(trigger='native repair full-map equality failure',direct_cause='unrelated E3 evictions cleared all visible terrain fade completion records; initial capture could also occur before a newly-started or deferred fade had settled',fix='C1 invalidates transition records only for affected resource pages; native wait rechecks command completion and all fades after the settle interval',evidence='01/02 preserve failures; 03/04 keep exact repair equality and pass; no thresholds loosened',old_e3_rewritten=False))
    run(evidence,'repository',[sys.executable,'verify_repository.py']);run(evidence,'plugin_source',[sys.executable,'plugin-source/verify_source.py']);run(evidence,'sealed_protection',[sys.executable,'tools/verify_review_protection.py']);run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise RuntimeError(scope['errors'])
    config=read(work/'SOURCE_RUNTIME/v02/c1/config.json');packages={}
    for key in config['packages']:
        base=work/'SOURCE_RUNTIME'/config['packages'][key]['path'][6:]
        packages[key]=dict(package_sha256=sha(base/'presentation.package.json'),catalog_sha256=sha(base/'world.catalog.json'),manifest=read(base/'presentation.package.json'),catalog=read(base/'world.catalog.json'),provenance=read(base/'receipts/provenance.json'))
    save(evidence/'packages.json',packages)
    extras=[*sorted((ROOT/'tools/map_v02').glob('c1_*.py')),ROOT/'docs/map_v02/C1_INTEGRATION.md']
    save(evidence/'supplemental_sources.json',dict(files=[dict(path=f.relative_to(ROOT).as_posix(),sha256=sha(f)) for f in extras]))
    release=ROOT/'Release';release.mkdir(exist_ok=True)
    archive=release/(a.build_id+'_windows_review.zip')
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
        for file in sorted((work/'CLEAN_WINDOWS').iterdir()):z.write(file,file.name)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise RuntimeError('zip CRC')
    save(evidence/'archive.json',dict(path=str(archive),sha256=sha(archive),bytes=archive.stat().st_size,crc_passed=True,publication='local_review_candidate_only'))
    positives=[r for r in native['gpu_comparisons'] if r['expect_equal']];negative=next(r for r in native['gpu_comparisons'] if not r['expect_equal'])
    save(report/'visual_review.json',dict(build_id=a.build_id,status='pending',author='awaiting_user',source_manifest_sha256=sha(work/'SOURCE_MANIFEST.json'),artifacts=read(work/'ARTIFACTS.json'),cameras=['composition','courtyard','region','far','simplified'],opinion=None))
    save(report/'ACCEPTANCE.json',dict(stage='C1',build_id=a.build_id,technical='passed',visual='pending',history='not_signed',q1='not_claimed',native_checks=native['checks'],compatibility_suites=11,old_files_unchanged=len(before),old_art_overwritten=False,new_ai_art_count=0,mip_scope='base only',gpu_positive_cases=len(positives),gpu_negative_control='detected',original_authority='one controller/context; Save22 unchanged',normal_profile='256/320 MiB',pressure_profile='32/48 MiB engineering test only'))
    observations=native['observations'];cycles=[r for r in observations if r['case'].startswith('reload_')]
    count=len(list((report/'native').glob('*.png')))
    text=f'''# C1：地形、院落与损毁修复接入 E1—E3

构建 `{a.build_id}`。原生功能检查 **{native['checks']} 项通过**，11 组兼容回归通过；视觉审阅 **pending**。这是一份可操作的 C1 整合候选，Q1 完整性能与历史准确性未签署。

## 启动与审阅

[启动整合版](H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/CLEAN_WINDOWS/Start-C1.cmd)。可编辑 Godot 项目：[project.godot](H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/SOURCE_RUNTIME/project.godot)，入口 `v02/c1/main.tscn`。

- **1—4**：关河组合、院落近景、区域地势、东亚粗示意。滚轮连续缩放，拖动平移，点击地点保持选中回执。语义图标／剪影／简化布局／详细院落与纹理页分辨率各自选择，均有迟滞。
- **U / R**：卸载显示／重载当前视野。可先 **C** 回建设前、**B** 按原合同开工，**U** 卸载、按 **D** 三次推进原有三天，再 **X** 损毁，最后 **R** 重载检查最新状态、**F** 原位修复。
- **H / J**：原成长档位／主关开闭；**G / T**：地块分页线／地形独显。
- **5 / N**：同一加载器的 256 页、256 工程地点夹具／跳往下一片；**Tab / K**：工程势力覆盖／归属颜色切换。工程内容与原东亚粗底图均为示意。

![整合画面](H:/tongguan_reviewfix_20261015/reports/map_v02/{a.build_id}/native/final_composition.png)

![远景代理](H:/tongguan_reviewfix_20261015/reports/map_v02/{a.build_id}/native/lod_far.png)

## 实际整合

启动阶段沿用原 V2 Session 创建唯一 FinalController／GameState／Context；没有初始化旧六块地形缓存。新 C1 服务继承 E3 MapService，继续使用原 E1 包验证、E2 反向空间桶／稳定绘制计划与增量更新、E3 后台请求／采用预算／真实引用释放。原 E1—E3、V1／V2／R1 代码保持不变。

R1 地面与水层在新构建目录确定性合成，12 个细页 core1024、gutter32、512m 范围保持，概览沿用原24×16km数据。全部建筑、墙段损毁、树、军队、标签及工程势力保留动态层。未新增AI美术，未更改关门、八地块、道路接点、生成器、Save22或原图。

原 V1 accepted 收据只证明原 V1 风格；`receipts/terrain_review.json` 另记 V2／R1 候选与“好很多”的反馈，C1 整体仍待本次审阅。完整参考纹理仅在 GPU 检查时临时载入并释放，交互入口不持有。

当前权威的 site／slot／建筑ID、建设与损毁映射通过 E2 delta 更新。模型不因 LOD 或资源加载随机重排；存档制作内容与表现包摘要不匹配会明确拒绝候选显示，保留原权威内容。

## 验证证据

原生干净 Windows 包实际1920×1080、{count}张未修图截图；退出0，无 ERROR／WARNING／泄漏诊断。运行命令、构建哈希、逐次绘制命令、原合同和时钟收据在 [native/result.json](native/result.json)。

| 检查 | 本次结果 |
|---|---|
| 全尺度往返 | 地点选中、原 controller/context、游戏状态、锚点保持；详细资源未就绪保留代理 |
| 迟滞 | 三个语义阈值各20次、实际纹理阈值20次往返；无切换抖动或额外请求风暴 |
| 多层覆盖 | 抽走细页实际纹理后仍解析到同构建概览；恢复后同机位像素完全一致 |
| 离屏建设 | 原合同实付120钱／20木，卸载不改日期／暂停，原时钟推进3天后完成仓库；重载读取最新损毁 |
| 原位修复 | 地图区域修复前后完全逐像素一致，接地点不变 |
| 卸载重载 | 5个周期均无存活退役纹理弱引用，重载截图完全一致；固定末视野驻留字节 `{[r['telemetry']['residency']['accounting']['resident'] for r in cycles]}` |
| 标签与势力 | 实际屏幕标签最多64且避让；选中地点独立回执，归属颜色改变不请求／重建地形 |
| 预算 | 默认256/320MiB与独立32/48MiB压力配置；压力回退不改玩法、恢复默认后细节恢复 |
| GPU页对照 | 七个缩放／交界正向对照，预先冻结最大通道差1，实测最大{max(r['max_channel_delta'] for r in positives)}；40m错位反向对照最大差{negative['max_channel_delta']}，成功检出 |
| 导入像素 | {native['verified_texture_count']}个实际驻留纹理GPU读取的基础层哈希与清单一致 |

11组兼容回归包含C1策略、V2状态、E3生命周期、E2查询、E1适配、几何、owner、发布、通道、建设、Save22。开工前保护的 **{len(before)}个文件SHA全部未变**，复用运行源与导出暂存逐文件相同；仓库、插件空素材、旧封存、范围及空白检查通过。没有提交、推送或外部发布。

首轮发现无关资源淘汰使可见地形重新淡化，C1仅失效受影响页的过渡记录；同时收紧测试的“稳定画面”等待，防止在新淡化或延后绘制尚未完成时取图。01/02失败与03通过证据原样保留在development，修复／重载的像素相等要求未放宽。

## 审阅边界与回退

请审阅滚轮缩放的四档可读性、代理切换、父子地形接缝、院落／墙段遮挡与损毁修复组合。技术通过不代签画面。[visual_review.json](visual_review.json)为pending。

本次没有进行Q1的3×60秒＋300秒完整压力验收，也不宣称深mip或唐代历史地理准确。保留实际现代DSM、岸线和原东亚粗示意的来源边界。

回退只需关闭本候选、启动原R1／V2／旧入口。C1在独立 `user://tests/v02/c1/` 创建审阅检查点，没有迁移旧地图或旧存档。本地Windows候选ZIP位于 `Release/{archive.name}`，SHA与CRC见[evidence/archive.json](evidence/archive.json)。
'''
    (report/'REPORT.md').write_text(text,encoding='utf-8')
    save(report/'DELIVERY_MANIFEST.json',dict(build_id=a.build_id,files=[dict(path=f.relative_to(report).as_posix(),sha256=sha(f),bytes=f.stat().st_size) for f in source_files(report) if f.name!='DELIVERY_MANIFEST.json']))
    print('C1_READY',report,flush=True)
if __name__=='__main__':main()
