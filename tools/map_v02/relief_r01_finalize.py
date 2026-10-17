"""Seal a pending terrain revision with explicit numeric/native/visual boundaries."""
import argparse,re,shutil,sys,zipfile
import numpy as np
from PIL import Image
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_finalize import run

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;report=ROOT/'reports/map_v02'/a.build_id;report.mkdir(parents=True,exist_ok=False);evidence=report/'evidence';evidence.mkdir()
    native=read(work/'native_01/result.json');regressions=ROOT/'review-work/map_v02/relief_r01_regressions'
    if not native['technical_passed'] or not read(regressions/'summary.json')['passed']:raise RuntimeError('validation not passed')
    manifest=read(work/'SOURCE_MANIFEST.json')
    for row in manifest['files']:
        file=ROOT/row['path']
        if sha(file)!=row['sha256']:raise RuntimeError('source changed '+row['path'])
        if file.is_relative_to(RUNTIME) and sha(work/'SOURCE_RUNTIME'/file.relative_to(RUNTIME))!=row['sha256']:raise RuntimeError('stage changed')
    for name,row in read(work/'ARTIFACTS.json').items():
        if sha(work/'CLEAN_WINDOWS'/name)!=row['sha256'] or name in native['artifacts'] and native['artifacts'][name]!=row['sha256']:raise RuntimeError('tested artifact mismatch')
    before=read(ROOT/'review-work/map_v02/relief_r01_boundary/before.json')['files']
    changed=[r['path'] for r in before if not (ROOT/r['path']).is_file() or sha(ROOT/r['path'])!=r['sha256']]
    save(evidence/'protection.json',dict(passed=not changed,files=len(before),changed=changed))
    if changed:raise RuntimeError('pre-existing files changed')
    config=read(RUNTIME/'v02/relief_r01/terrain.json');brush=read(RUNTIME/'v02/relief_r01/structure_brushes.json')
    if not all(r['independent_global_equal'] and r['old_water_core_equal'] for r in config['tests']):raise RuntimeError('numeric tile identity')
    # Independent adjacent overlap comparisons include every edge of each layer.
    overlaps=[];base=RUNTIME/'v02/relief_r01/assets';g=config['gutter_px'];core=config['core_px']
    for kind in ['ground','water']:
        for y in range(3):
            for x in range(4):
                one=np.asarray(Image.open(base/f'{kind}_{x}_{y}.png')).astype(np.int16)
                if x<3:
                    two=np.asarray(Image.open(base/f'{kind}_{x+1}_{y}.png')).astype(np.int16);d=np.abs(one[:,core:]-two[:,:2*g]);overlaps.append(dict(kind=kind,x=x,y=y,edge='east',max_delta=int(d.max())))
                if y<2:
                    two=np.asarray(Image.open(base/f'{kind}_{x}_{y+1}.png')).astype(np.int16);d=np.abs(one[core:]-two[:2*g]);overlaps.append(dict(kind=kind,x=x,y=y,edge='south',max_delta=int(d.max())))
    if any(r['max_delta'] for r in overlaps):raise RuntimeError('base overlaps')
    save(evidence/'numeric_terrain.json',dict(analytic_checks=6,independent_pages=config['tests'],adjacent_overlap_checks=overlaps,source_height_sha256=config['source_height_sha256'],source_contours_sha256=config['source_contours_sha256'],brushes=brush,mip_scope='base only'))
    shutil.copytree(work/'native_01',report/'native',ignore=shutil.ignore_patterns('*.log'))
    shutil.copytree(regressions,evidence/'regressions')
    development=ROOT/'review-work/map_v02/relief_r01_boundary'
    (evidence/'development').mkdir()
    for path in development.iterdir():
        if path.is_file():shutil.copyfile(path,evidence/'development'/path.name)
    for name in ['SOURCE_MANIFEST.json','ARTIFACTS.json','import.json','import.txt','import_pixels.json','import_pixels.txt','export.json','export.txt']:shutil.copyfile(work/name,evidence/name)
    run(evidence,'analytic',[sys.executable,'tools/map_v02/test_relief_r01.py'])
    run(evidence,'repository',[sys.executable,'verify_repository.py']);run(evidence,'plugin_source',[sys.executable,'plugin-source/verify_source.py']);run(evidence,'sealed_protection',[sys.executable,'tools/verify_review_protection.py']);run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise RuntimeError(scope['errors'])
    save(report/'previous_v2_feedback.json',dict(source_build_id='tongguan_v02_v2_20261016_02',status='revision_requested',author='user',opinion='坡面、山脊和沟谷的结构表达仍偏弱；建议依据已有等高线组织地形',scope='terrain structure revision only; existing art/state/geometry preserved',old_review_files_rewritten=False))
    save(report/'visual_review.json',dict(build_id=a.build_id,status='pending',author='awaiting_user',source_manifest_sha256=sha(work/'SOURCE_MANIFEST.json'),terrain_manifest_sha256=sha(RUNTIME/'v02/relief_r01/terrain.json'),modes=['full_composition','terrain_only','original_contour_check'],cameras=['composition','shore','courtyard','region'],opinion=None))
    save(report/'GPU_COMPARISONS.json',dict(rows=native['gpu_comparisons'],scope='actual1600x940 map crop in actual1920x1080 native buffer; max delta frozen at1 before run; negative control requires mismatch'))
    extras=[*(ROOT/'tools/map_v02').glob('relief_r01_*.py'),ROOT/'tools/map_v02/test_relief_r01.py',ROOT/'docs/map_v02/V2_RELIEF_R01.md']
    save(evidence/'supplemental_sources.json',dict(files=[dict(path=f.relative_to(ROOT).as_posix(),sha256=sha(f)) for f in sorted(extras)]))
    archive=work/(a.build_id+'_windows.zip')
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
        for file in sorted((work/'CLEAN_WINDOWS').iterdir()):z.write(file,file.name)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise RuntimeError('zip CRC')
    save(evidence/'archive.json',dict(path=str(archive),sha256=sha(archive),bytes=archive.stat().st_size,crc_passed=True))
    positive=[r for r in native['gpu_comparisons'] if r['expect_equal']];negative=next(r for r in native['gpu_comparisons'] if not r['expect_equal'])
    content=f'''# V2 地形结构 R1：同高度场、等高线与组合审阅

构建 `{a.build_id}`，视觉状态 **pending**。响应作者关于坡面、山脊和沟谷表达弱、应依据等高线的反馈，新增独立数值地形表现候选。旧地图、旧素材、旧V1/V2/E3及原玩法源码均不覆盖。

## 操作与同机位对照

[启动审阅](H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/CLEAN_WINDOWS/Start-Relief-R1.cmd)。独立Godot工程：同构建目录SOURCE_RUNTIME/project.godot；可编辑数值地形场景SOURCE_RUNTIME/v02/relief_r01/terrain.tscn。

默认先看区域地势。F1完整组合、F2地形独显、F3原等高线校核，三者不改变镜头；F4回区域机位。O同机位新旧地形对照；原1—4关河/院落/墙楼/坡岸机位保留，拖动/滚轮连续平移缩放。右侧原建设、损毁、修复和成长/关门操作仍可用。

![区域地势](H:/tongguan_reviewfix_20261015/reports/map_v02/{a.build_id}/native/region_new_terrain.png)

![原等高线校核](H:/tongguan_reviewfix_20261015/reports/map_v02/{a.build_id}/native/composition_new_contours.png)

![新地形组合](H:/tongguan_reviewfix_20261015/reports/map_v02/{a.build_id}/native/composition_new_full.png)

每个近景机位另有new_full/new_terrain/new_contours/old_full，另保留12帧平移缩放、损毁和修复截图。全部来自实际Godot1920×1080缓冲，未后期修图。区域机位是原24×16km数值源的概览，不是新增历史节点或新地图。

## 改了什么

仍使用原600×400、40m现代DSM，SHA与原等高线记录相同。对整个高度场做40m/140m两档Gaussian分析，用坡度坡向法线、统一上左光向、多尺度凸凹关系及横坡曲率组织明暗。固定全局色阶与世界坐标采样，不逐页拉伸，也不按高度分类土地用途。高分辨率美术像素不增加测绘精度。

正式画面从源350/420/520m线中，仅选满足陡坡/凸凹条件的少量短段：本细页范围{len(brush['selected_source_features'])}个源feature、{brush['segments']}段浅笔触、{brush['slope_hatches']}条顺坡短笔触。完整256条原等高线只在校核视图显示。凸凹场/笔触是地势表现候选，不据此新增沟河、通行或历史地理事实。

去掉新表现中的旧规则岸边排线与手工坡脚示意，保留原水域遮罩、道路中心线和接点。水图细页核心与旧V1逐像素一致。建筑、树、墙、关楼均不因高度重投影/抬升或挪动；不改变原八地块及人工编辑/删除/固定。

细页范围保持[-1024,-1024,2048,1536]，12个地面页/12个水页，core1024px覆盖512m，gutter32px，当前仅线性基础层采样。另有原数值范围的概览和独立整幅参考。这些PNG全由确定性数值配方生成；没有新增AI绘制素材或批量生产建筑。

## 验证与保护

- 6项独立解析场检查通过：平面、坡向光照、凸/凹符号、世界采样、非法数值拒绝、边界采样。
- 12页分别重新求值，与整幅场一致；12页旧水core保持；34组相邻基础层重叠差均为0。
- Godot原生{native['checks']}项检查通过，退出0，无超时或ERROR/WARNING/资源泄漏诊断。模式/相机切换不改变原GameState，原建设真实扣120钱/20木并经3日结算，损毁/修复后同机位地图像素完全恢复，建筑/墙变换、合同和经济不变。
- 4档缩放(.42/.84/1.4/2.4)与3处交界的分页/整幅实际GPU对照全部通过。阈值在测试前冻结为单通道最大差1；实际最大{max(r['max_channel_delta'] for r in positive)}，不是“完全逐像素相同”。差异像素数见[GPU_COMPARISONS.json](GPU_COMPARISONS.json)。
- 注入一页错移40m的反向对照得到最大差{negative['max_channel_delta']}，成功检出；注入只在测试进程中，已恢复，未写源场景。
- 原V2状态、几何、建设、owner、发布、通道、Save22共7组回归通过。存档使用原fixture目录和独立测试输出。开工前保护清单{len(before)}个文件SHA均未变；插件空素材、仓库范围、旧封存和空白检查通过。未提交、推送或发布。

01开发构建通过125项；02将整幅参考改为验证时才载入、默认先展示区域地势，为最终交付。早期纯明暗数值草稿保留在review-work/map_v02/relief_r01_boundary/first_numeric_draft；原始失败测试输出未覆盖。

## 审阅边界

请主要判断：关闭建筑和树后能否读懂塬面/坡向/沟谷；完整等高线与地势是否相符；近景是否仍过软、结构笔触是否自然。技术检查不代签这些判断，[visual_review.json](visual_review.json)保留pending。旧V2作者反馈另存[previous_v2_feedback.json](previous_v2_feedback.json)，不覆写旧收据。

这仍是固定地面映射的二维表现，不是3D地面形变。没有从40mDSM编造米级地形；现代DSM、岸线和候选关址不能直接证明756年地形。完整历史复原未签署。

本入口为新旧A/B和可见结构审阅，保留旧/新表现资源；不把它称为生产预算或E3流式整合验证。整幅参考仅验证时载入；深mip、完整混合LOD、Q1帧时/显存预算和C1正式整合未在本次签署。旧V2三张资产、原Session权威服务、旧默认入口均不变。拒绝本候选时关闭窗口启动原V2即可，无存档/地图迁移。
'''
    (report/'REPORT.md').write_text(content,encoding='utf-8')
    save(report/'ACCEPTANCE.json',dict(stage='V2_relief_R1',build_id=a.build_id,technical='passed',visual='pending',script_checks=native['checks'],analytic_checks=6,gpu_positive_cases=len(positive),gpu_negative_control='detected',old_files_unchanged=True,mip_scope='base only',c1='not_implemented',q1='not_claimed',history='modern reference only'))
    save(report/'DELIVERY_MANIFEST.json',dict(build_id=a.build_id,files=[dict(path=f.relative_to(report).as_posix(),sha256=sha(f),bytes=f.stat().st_size) for f in source_files(report) if f.name!='DELIVERY_MANIFEST.json']))
    print('RELIEF_READY',report,flush=True)

if __name__=='__main__':main()
