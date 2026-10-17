"""Collect bounded V1 review evidence; never grants visual acceptance."""
from pathlib import Path
import argparse, html, json, re, shutil, subprocess, sys, zipfile
import numpy as np
from PIL import Image
from common import ROOT, RUNTIME, read, save, sha, source_files, scope_check
from v1_build import GODOT


def run(folder, name, command):
    folder.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=150)
    raw = result.stdout + result.stderr
    (folder / (name + '.txt')).write_bytes(raw)
    diagnostics = re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$', raw.decode('utf-8', errors='replace'), re.M)
    value = dict(command=command, exit_code=result.returncode, diagnostics=diagnostics,
                 passed=result.returncode == 0 and not diagnostics)
    save(folder / (name + '.json'), value)
    if not value['passed']:
        raise RuntimeError(str(folder / (name + '.txt')))
    print('V1_CHECK', name, 'PASS', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-id', required=True)
    a = parser.parse_args()
    if not re.fullmatch('[a-zA-Z0-9_-]+', a.build_id):
        raise ValueError('build id')
    work = ROOT / 'review-work/map_v02' / a.build_id
    report = ROOT / 'reports/map_v02' / a.build_id
    report.mkdir(parents=True, exist_ok=False)
    evidence = report / 'evidence'
    evidence.mkdir()
    captures = work / 'capture_01'
    native = read(captures / 'result.json')
    if not native['technical_passed']:
        raise RuntimeError('native capture failed')
    for row in read(work / 'SOURCE_MANIFEST.json')['files']:
        source = ROOT / row['path']
        staged = work / 'SOURCE_RUNTIME' / source.relative_to(RUNTIME)
        if sha(source) != row['sha256'] or sha(staged) != row['sha256']:
            raise RuntimeError('source/build drift: ' + row['path'])
    for name, row in read(work / 'ARTIFACTS.json').items():
        if sha(work / 'Windows' / name) != row['sha256']:
            raise RuntimeError('artifact changed: ' + name)
        if name in native['artifacts'] and native['artifacts'][name] != row['sha256']:
            raise RuntimeError('tested artifact drift: ' + name)
    # The raw .log stays in local review-work; its byte-identical runtime.txt
    # is included as evidence without violating source publication rules.
    shutil.copytree(captures, report / 'captures', ignore=shutil.ignore_patterns('*.log'))
    for name in ['ARTIFACTS.json', 'SOURCE_MANIFEST.json', 'export.json', 'export.txt', 'import.json', 'import.txt', 'import_mips.json', 'import_mips.txt']:
        shutil.copyfile(work / name, evidence / name)
    boundary = ROOT / 'review-work/map_v02/v1_boundary'
    development = evidence / 'development'
    development.mkdir()
    for name in ['red_contract.json', 'placement_02.json', 'protection_and_seams.json']:
        shutil.copyfile(boundary / name, development / name)
    save(development / 'previous_builds.json', dict(
        builds=['tongguan_v02_v1_20261015_01', 'tongguan_v02_v1_20261015_02', 'tongguan_v02_v1_20261015_03'],
        location='review-work/map_v02/',
        excluded_from_final=True,
        notes=['first assembly exposed a visible field edge and a hidden north wall',
               'second assembly required socket overlap adjustment',
               'pre-final page overlap check found nine differing alpha values on five water edges; fixed by global mask slicing']))

    run(evidence, 'contract_run', [GODOT, '--headless', '--path', str(work / 'SOURCE_RUNTIME'), '--script', 'res://tests/v02/test_v1_composition.gd', '--', '--report=' + str(evidence / 'contract_result.json')])
    run(evidence, 'placement_run', [GODOT, '--headless', '--path', str(ROOT / 'samples/tongguan_v01/authoring'), '--script', str(ROOT / 'tools/map_v02/v1_check_placement.gd'), '--', '--report=' + str(evidence / 'placement_result.json')])
    before = read(boundary / 'before.json')['files']
    changed, missing = [], []
    for row in before:
        path = ROOT / row['path']
        if not path.is_file():
            missing.append(row['path'])
        elif sha(path) != row['sha256']:
            changed.append(row['path'])
    protection = dict(before_files=len(before), changed=changed, missing=missing,
                      allowed_changes=['verify_repository.py'],
                      passed=not missing and changed == ['verify_repository.py'],
                      reason='only repository verifier gains V1 receipt validation; all pre-V1 art, runtime, S0 receipts and prior reports retain their bytes')
    save(evidence / 'pre_v1_protection.json', protection)
    if not protection['passed']:
        raise RuntimeError('pre-V1 protection')

    v1 = RUNTIME / 'v02/v1'
    pages = v1 / 'assets/terrain_v01'
    edges = []
    for kind in ['ground', 'water']:
        for y in range(3):
            for x in range(4):
                first = np.asarray(Image.open(pages / f'{kind}_{x}_{y}.png'))
                for dx, dy, axis in [(1, 0, 'east'), (0, 1, 'south')]:
                    if x + dx >= 4 or y + dy >= 3:
                        continue
                    second = np.asarray(Image.open(pages / f'{kind}_{x+dx}_{y+dy}.png'))
                    left, right = (first[:, 1024:1032], second[:, :8]) if dx else (first[1024:1032], second[:8])
                    delta = np.abs(left.astype(int) - right.astype(int))
                    edges.append(dict(kind=kind, x=x, y=y, edge=axis, max_delta=int(delta.max()), different_values=int(np.count_nonzero(delta))))
    seams = dict(checks=len(edges), passed=all(r['max_delta'] == 0 for r in edges), edges=edges,
                 scope='source base-level overlapping gutters only; not a full mip, streaming or Q1 certificate')
    save(evidence / 'page_overlaps.json', seams)
    if not seams['passed']:
        raise RuntimeError('page overlap mismatch')
    run(evidence, 'sealed_protection', [sys.executable, 'tools/verify_review_protection.py'])
    shutil.copyfile(ROOT / 'review-work/protection.json', evidence / 'sealed_protection_result.json')

    style = read(v1 / 'style.json')
    manifest = read(v1 / 'manifest.json')
    archive = work / (a.build_id + '_windows.zip')
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted((work / 'Windows').iterdir()):
            bundle.write(path, path.name)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise RuntimeError('zip CRC')
    save(evidence / 'archive.json', dict(path=str(archive), bytes=archive.stat().st_size, sha256=sha(archive), crc_passed=True))
    save(report / 'visual_review.json', dict(
        stage='V1', build_id=a.build_id, style_id=style['style_id'],
        manifest_sha256=sha(v1 / 'manifest.json'), style_sha256=sha(v1 / 'style.json'),
        cameras=list(style['cameras']), status='pending', author=None, opinion=None,
        decisions=['accepted', 'revision_requested', 'rejected'],
        camera_reviews=[dict(camera=k, status='pending', opinion=None) for k in style['cameras']],
        automatic_checks_do_not_grant_acceptance=True))
    save(evidence / 'tool_sources.json', dict(files=[dict(path=p.relative_to(ROOT).as_posix(), sha256=sha(p)) for p in sorted((ROOT / 'tools/map_v02').glob('v1_*.py'))]))
    shutil.copyfile(ROOT / 'docs/map_v02/v1_wall_prompt.txt', evidence / 'wall_prompt.txt')
    shutil.copyfile(ROOT / 'docs/map_v02/v1_courtyard_prompt.txt', evidence / 'courtyard_prompt.txt')

    card = f'''# V1 风格卡：候选 A

构建 `{a.build_id}`；`visual_review=pending`。原始三张参考图未在交接目录中找到，这轮以现有选定关楼和树图集为画风锚点，不宣称与缺失参考图精确匹配。

## 参考取样和显示尺寸

| 标识 | 原图范围 / 接地点 | 用途 |
|---|---|---|
| GATE-OLD | gate_eastwest.png 全图 1536×1024；锚点 (665,690) | 旧关楼原样复用；墙体色、青瓦与线条参照 |
| TREE-WILLOW | trees.png / Rect(1024,0,512,512)；锚点 (256,399.36) | 柳树 |
| TREE-GROVE | trees.png / Rect(512,512,512,512)；同锚点 | 杂树林簇 |
| WALL-A01 | 新透明图 1536×1024；锚点 (433,390) | 单一 NW—SE 墙段，未旋转或镜像；以重叠端面接旧关楼 |
| COURT-A01 | 新透明图 1536×1024；锚点 (788,660) | 小仓储院落，保持原地块中心 (-567.5,-227.5)m |

1×指打开原生截图为1920×1080像素，而非把网页自适应缩图当作原生尺寸。在关楼机位，旧关楼整图投影宽约693px，新墙整图约452px；院落机位整图投影宽192px。均保留透明边界，以原生截图检查有效轮廓。

## 地面轴、屋顶、接点与光向

原地图固定东向 +X、南向 +Y；镜头只有平移缩放。两条地图地面轴以关楼原点显示在 G 参考层。建筑斜俯视来自栅格图，未把地图改为另一套等轴投影。

建筑画面参考轴：沿墙轴 u=(625,510)px；院落底边参考轴 u=(380,375)px、v=(460,-245)px。这些是素材边线方向，不能当作地理轴或移动授权。屋脊沿素材固定方向，墙段沿 NW—SE；不单独旋转图层补角度。理想主光从屏幕左上 (-0.6,-0.8)，阴影偏右下；旧关楼、树与新增资产是否协调仍待人工审阅。

G 显示实际关楼锚点、南北墙接点、原通道、八地块轮廓和512m页界。北端接点重叠 (7,6)m，南端插入 (8,2)m；接点误差小于0.001m是坐标校验，不能代替端面美术检查。

线条目标：关楼机位约0.7—1.2px细墨线；树叶密度沿用旧图集，地面低对比水洗纹理。现阶段岸边笔触较规则、土地坡感较弱，建筑线条比地形更硬，列为审阅问题。

## 固定机位

| 键 | 相机 | 本地中心 m | 缩放 |
|---|---|---|---|
'''
    for i, (key, camera) in enumerate(style['cameras'].items(), 1):
        card += f"| {i} | {key} / {camera['name']} | {camera['center_m']} | {camera['zoom']} |\n"
    card += '\n色样见 [审阅页](review.html)；色值和资产哈希以 [style.json](../../../samples/tongguan_v01/runtime/v02/v1/style.json) 为准。\n\n[关楼参考层原生图](captures/gate_guides.png) · [坡岸原生图](captures/shore_new.png) · [院落原生图](captures/courtyard_new.png)\n'
    (report / 'STYLE_CARD.md').write_text(card, encoding='utf-8')
    swatches = ''.join(f'<span class="swatch"><i style="background:#{c}"></i>{html.escape(k)} <code>#{c}</code></span>' for k, c in style['palette'].items())
    options = ''.join(f'<option value="{key}">{html.escape(camera["name"])}</option>' for key, camera in style['cameras'].items())
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>潼关 V1 组合审阅</title>
<style>body{margin:0;background:#e7e1d2;color:#243b3a;font:16px/1.6 "Microsoft YaHei",sans-serif}header,section{padding:20px 28px}h1{margin:0;font-size:26px}p{margin:8px 0}nav{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}button,select{padding:9px 14px;border:1px solid #8c998c;background:#fffdf5;color:#243b3a;border-radius:4px;font:inherit}figure{margin:0;overflow:auto;background:#273c3c}figure img{display:block;width:100%;max-width:1920px;margin:auto}figure.native img{width:1920px;max-width:none}.swatch{display:inline-flex;align-items:center;gap:8px;background:#fff9eb;padding:7px 12px;margin:4px;border-radius:3px}.swatch i{width:30px;height:30px;border:1px solid #7e8575}code{font-size:13px}a{color:#2b625d}small{display:block}input[type=range]{width:320px}</style>
<header><h1>潼关 V1 · 坡岸、水、树、道路、墙、关楼</h1><p>候选 A · 待作者审阅 · BUILD_ID</p><p>复用旧关楼与树图集，仅补两张透明素材。截图均来自 Godot 原生 Windows Release。</p>
<nav><select id="camera">OPTIONS</select><button id="compare">切到旧画面</button><button id="guides">关楼接点与参考线</button><button id="terrain">仅看地形</button><label><input id="native" type="checkbox">1× 原生像素</label></nav><small id="caption">关河组合 / 新小样 / 1920×1080</small></header>
<figure id="frame"><img id="shot" src="captures/composition_new.png" alt="Godot组合小样"></figure>
<section><h2>平移与缩放序列</h2><input id="sequence" type="range" min="0" max="23" value="0"><span id="seqText">0 / 23</span><p>24帧来自同一引擎场景和连续相机移动；用于审查画面，不是性能或流式容量验收。</p>
<h2>色样</h2>SWATCHES
<h2>本轮待看</h2><p>坡面是否连贯、岸边是否过于整齐、树木与关楼的线条及尺度是否协调、道路穿门和墙段端面是否自然。土地仍偏平，损毁仅用变色示意。</p>
<p><a href="STYLE_CARD.md">风格卡与参考裁切标识</a> · <a href="REPORT.md">检查和边界报告</a> · <a href="visual_review.json">待审记录</a> · <a href="captures/composition_new.png">打开原生组合图</a></p></section>
<script>let old=false;const shot=document.getElementById('shot'),camera=document.getElementById('camera'),caption=document.getElementById('caption');function show(name,label){shot.src='captures/'+name+'.png';caption.textContent=label+' / 1920×1080'}function recall(){show(camera.value+(old?'_legacy':'_new'),camera.selectedOptions[0].text+' / '+(old?'旧画面':'新小样'));document.getElementById('compare').textContent=old?'切到新小样':'切到旧画面'}camera.onchange=recall;document.getElementById('compare').onclick=()=>{old=!old;recall()};document.getElementById('guides').onclick=()=>show('gate_guides','实际锚点、接点、地面参考线');document.getElementById('terrain').onclick=()=>show('terrain_only','仅地形');document.getElementById('native').onchange=e=>document.getElementById('frame').classList.toggle('native',e.target.checked);document.getElementById('sequence').oninput=e=>{const n=+e.target.value;show('sequence_'+String(n).padStart(2,'0'),'平移缩放序列 '+n);document.getElementById('seqText').textContent=n+' / 23'};</script></html>'''
    (report / 'review.html').write_text(page.replace('BUILD_ID', a.build_id).replace('OPTIONS', options).replace('SWATCHES', swatches), encoding='utf-8')

    text = f'''# 潼关 V1 组合小样：候选 A，待审

构建 `{a.build_id}`；风格 `{style['style_id']}`。本轮完成可编辑 Godot 组合、独立 Windows 启动包、固定机位新旧对照与接点参考层。作者审阅状态 **pending**；不自动进入美术扩充。

[打开审阅页](review.html) · [风格卡](STYLE_CARD.md) · [待审记录](visual_review.json) · [原生组合图](captures/composition_new.png)

## 启动与编辑

直接启动 `H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/Windows/Start-V1.cmd`。旁边的 exe 与 pck 必须放在一起；zip 校验信息在 evidence/archive.json。

源场景：[composition.tscn](../../../samples/tongguan_v01/runtime/v02/v1/composition.tscn)。该场景为原生 Sprite2D/Node2D，可在 Godot 中编辑。入口是同目录 main.tscn；冻结运行工程在 `review-work/map_v02/{a.build_id}/SOURCE_RUNTIME`，默认启动此 V1。原工程默认入口未改。

按1—4切固定机位；B新旧画面对照；G实际锚点、接点和参考线；T仅地形；滚轮缩放，拖动平移，Esc退出。建设前后/损毁/恢复按钮用于单一仓储原位状态示意。

## 范围与来源

12类组合部件：连续土地、水、岸边、坡脚、石块、主路、接路、关楼、短墙、仓储院落、柳树、杂树林簇。不是12张新图。新绘制素材仅 `wall_ns_v01.png` 与 `warehouse_v01.png` 两张，生成提示和哈希已保存；关楼、两种树均复用旧 PNG/图集裁切。24张地形/水分页来自同一个连续数值场，属于数值表现，不是批量生成的新建筑美术。

数值地形沿用600×400、40m高度场；表现采样2px/m，范围2048×1536m，4×3页，每页512m/1024px核心、4px边缘。高分辨率纹理不增加地形测绘精度，水形来自现代参照，未宣称756年实测。原始高度、水域和布局数据未改。

原关门、八地块、通道/支路接点、ID、锁定/隐藏规则、Save22/v4、空插件注册表及旧素材未变。新候选树只在本次演示场景摆放；不会写回旧地图或 presentation.instances。仓储保持旧地块中心，新增门前短接路仅为表现层。

仓储建设演示调用原建设服务，从旧初始资源实际支付120钱、20木材，三步完成后剩120钱、60木材；没有第二套账户或GameState。测试存档在独立用户目录 `tongguan_v02_v1_review/tests/map_v02/v1`。损毁只使用原损毁状态并调色，不是成套废墟资产。

## 已完成检查

- Windows Release实际1920×1080截图与原生检查：{native['checks']}项通过，诊断为空；38张原始截图（四机位新旧8张、参考层/地形2张、建设/损毁/恢复4张、连续平移缩放24张）。
- 源场景契约：16项通过；原关楼未旋转、原地块中心、接点误差<0.001m、读场景不改共享状态等。几何接点通过不等于端面画风通过。
- 使用原制作端完整占地与保护规则复查13个新候选树位；道路/水线/地块保护无冲突，仓储地面多边形位于原45×25m地块内，原制作端状态未变。
- 土地及水面34条相邻页边缘重叠区逐像素完全相同。此项只证明基础采样一致，不是全mip链、流式或Q1验证。
- 对开工前{len(before)}个已有文件逐一比哈希：只有 `verify_repository.py` 增补V1清单验证；其余{len(before)-1}个文件原样保留。S0源码及冻结收据、旧素材、旧报告均未覆盖；另检旧封存包和发布基线。
- 仓库验证、插件零美术验证、范围与空白检查的命令、退出码、原始输出见 evidence/。未为纯视觉小样重跑S0长性能测试，不据此宣称性能已达标。

## 修正记录与待审问题

开发构建01—03保存在review-work，本次交付只使用04。首轮发现地形边缘露出、北墙被地形遮住，随后修正显示范围与层级；墙端插入量经原生近景调整。原制作端检查曾发现两棵候选树靠水保护带，已只移动这两棵新增树。逐页栅格化产生的9个水遮罩alpha差异已改为全域遮罩裁页，最终34条重叠边检查全通过。首次报告收集误带了本地.log，被仓库检查阻止；原始日志仍在review-work，报告仅收录相同内容的.txt。原失败记录保留在evidence/development/及历史构建。

尚待作者判断：土地坡感仍弱，岸边短段较规则，树与建筑线条密度差异、院落相对关楼尺度、道路穿门和墙端过渡是否自然。缺失原始三张参考图，不能宣称已精确对齐参考风格。损毁仅是占位示意；另一方向墙、转角、驻军/民居组团及完整损毁资源未扩充。

只完成V1首轮可审阅组合；**美术认可、V1全部验收、V2、E1/E2/E3、第二节点、全国容量、Q1均不在本次完成声明中**。没有提交、推送或发布。

## 版本和回退

V1独立清单哈希：`{sha(v1 / 'manifest.json')}`；风格卡数据哈希：`{sha(v1 / 'style.json')}`。清单与Windows哈希在evidence/。

关闭本次独立程序，继续启动原S0/旧入口即可回到原显示；无需删除、回写或迁移任何旧地图。V1源文件集中在runtime/v02/v1和tests/v02/test_v1_composition.gd；未修改旧入口运行行为。当前工作区还保留上一批S0未提交改动，不能把本次V1清理等同于整库重置。
'''
    (report / 'REPORT.md').write_text(text, encoding='utf-8')
    run(evidence, 'repository', [sys.executable, 'verify_repository.py'])
    run(evidence, 'plugin_source', [sys.executable, 'plugin-source/verify_source.py'])
    run(evidence, 'whitespace', ['git', '-c', 'core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol', 'diff', '--check'])
    scope = scope_check()
    save(evidence / 'scope.json', scope)
    if not scope['passed']:
        raise RuntimeError('scope')
    save(report / 'DELIVERY_MANIFEST.json', dict(build_id=a.build_id, visual_review='pending',
        files=[dict(path=p.relative_to(report).as_posix(), sha256=sha(p), bytes=p.stat().st_size) for p in source_files(report) if p.name != 'DELIVERY_MANIFEST.json']))
    print('V1_READY', report, flush=True)


if __name__ == '__main__':
    main()
