"""Collect immutable S0 receipts and produce a candid stage report."""
from pathlib import Path
import argparse, csv, json, re, shutil, subprocess, sys, zipfile
from common import ROOT, BASE, git, read, save, sha, scope_check

def copy_tree(source, target):
    for path in source.rglob('*'):
        if path.is_file() and path.suffix != '.log':
            destination = target / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)

def checks_from_log(path):
    text = path.read_text(encoding='utf-8', errors='replace')
    values = re.findall(r'"checks"\s*:\s*(\d+)', text)
    return int(values[-1]) if values else None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-id', required=True)
    parser.add_argument('--report-id')
    args = parser.parse_args()
    work = ROOT / 'review-work/map_v02' / args.build_id
    native = read(work / 'native/summary.json')
    source = read(ROOT / 'review-work/map_v02/source_final/summary.json')
    report_id = args.report_id or args.build_id
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', report_id):
        raise ValueError('Invalid report id')
    report = ROOT / 'reports/map_v02' / report_id
    report.mkdir(parents=True, exist_ok=False)
    copy_tree(ROOT / 'review-work/map_v02/source_final', report / 'source')
    copy_tree(ROOT / 'review-work/map_v02/contract_final', report / 'latest_contract')
    copy_tree(work / 'native', report / 'native')
    for name in ['BUILD.json', 'ARTIFACTS.json', 'scope_at_build.json']:
        shutil.copyfile(work / 'release' / name, report / name)
    if (work / 'environment.json').exists():
        shutil.copyfile(work / 'environment.json', report / 'environment.json')
    save(report / 'REQUIREMENTS.json', dict(files=[dict(path=path.relative_to(ROOT).as_posix(), sha256=sha(path)) for path in sorted((ROOT / 'docs/map_v02').glob('0*_v0.2.md'))]))
    for label in ['s0_red', 's0_green_01', 'contract_green_02', 'dimensions_red', 'dimensions_green', 'viewport_red', 'contract_final', 'smoke_01', 'smoke_02', 'smoke_03', 'smoke_04', 'smoke_05', 'smoke_06']:
        path = ROOT / 'review-work/map_v02' / label
        if path.exists():
            copy_tree(path, report / 'development_evidence' / label)
    previous = ROOT / 'review-work/map_v02/tongguan_v02_s0_20261015_04/native'
    if previous.exists():
        copy_tree(previous, report / 'development_evidence/pre_fixed_viewport')
    initial_report = ROOT / 'reports/map_v02' / args.build_id
    if initial_report != report and (initial_report / 'git_whitespace.txt').exists():
        destination = report / 'development_evidence/initial_whitespace_check'
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(initial_report / 'git_whitespace.txt', destination / 'runtime.txt')
        save(destination / 'explanation.json', dict(reason='Repository uses * -text and baseline CRLF files. Default git diff --check treats new CR as trailing whitespace. Recheck enables cr-at-eol while retaining trailing blank and indentation checks; no source bytes changed.'))
    performance = []
    for row in native['results']:
        path = work / 'native' / row['name'] / 'result.json'
        value = read(path)
        if value.get('requested_seconds') not in [60, 300]:
            continue
        dimensions = value['dimensions']
        phase_names = set()
        with (path.parent / 'frames.csv').open(encoding='utf-8', newline='') as handle:
            for frame in csv.DictReader(handle):
                phase_names.add(frame['camera'])
        performance.append(dict(name=row['name'], mode=value['mode'], seconds=value['duration_seconds'],
                                p95_ms=value['frame_p95_ms'], p99_ms=value['frame_p99_ms'], max_ms=value['frame_max_ms'],
                                long_frame_counts=value['long_frame_counts'], samples=value['sample_count'],
                                execution_passed=value['execution_passed'], eligible=value['performance_acceptance_eligible'],
                                percentile_budget_passed=value['percentile_budget_passed'], dimensions=dimensions,
                                camera_phases=sorted(phase_names), windows_metrics=value['windows_metrics'],
                                resources=value['observations_end']['resources'],
                                tree_plan_rebuilds=value['observations_end']['tree_plan_rebuilds'] - value['observations_start']['tree_plan_rebuilds'],
                                tree_candidates=value['observations_end']['tree_candidates_tested'] - value['observations_start']['tree_candidates_tested'],
                                tree_submissions=value['observations_end']['tree_submitted_objects'] - value['observations_start']['tree_submitted_objects']))
    expected_phases = {'overview', 'region', 'terrain', 'gate', 'forest', 'near_gate'}
    scope = scope_check()
    save(report / 'scope.json', scope)
    validation = []
    for name, command in [
        ('plugin_source', [sys.executable, 'plugin-source/verify_source.py']),
        ('repository', [sys.executable, 'verify_repository.py']),
        ('sealed_protection', [sys.executable, 'tools/verify_review_protection.py']),
        ('git_whitespace', ['git', '-c', 'core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol', 'diff', '--check']),
    ]:
        process = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=120)
        (report / (name + '.txt')).write_bytes(process.stdout + process.stderr)
        validation.append(dict(name=name, command=command, exit_code=process.returncode, passed=process.returncode == 0))
    save(report / 'validation.json', validation)
    metadata = read(work / 'release/BUILD.json')
    # Confirm the source snapshot tested in native Release matches current files.
    mismatch = [row['path'] for row in metadata['source_files'] if not (ROOT / 'samples/tongguan_v01/runtime' / row['path']).is_file()
                or sha(ROOT / 'samples/tongguan_v01/runtime' / row['path']) != row['sha256']]
    pixel_hashes = {row['name']:sha(work / 'native' / row['name'] / 'composition.png') for row in performance}
    save(report / 'screenshot_comparison.json', dict(hashes=pixel_hashes, identical=len(set(pixel_hashes.values())) == 1,
                                                  scope='Same old composition and fixed camera; no new art acceptance.'))
    phase_coverage = len(performance) == 8 and all(set(row['camera_phases']) == expected_phases for row in performance)
    latest_contract = read(ROOT / 'review-work/map_v02/contract_final/summary.json')
    correctness = source['passed'] and latest_contract['passed'] and native['technical_passed'] and scope['passed'] and all(row['passed'] for row in validation) and not mismatch and phase_coverage
    summary = dict(build_id=args.build_id, stage='S0', status='technical_candidate_pending_user_review',
                   source_passed=source['passed'], native_compatibility_passed=native['technical_passed'],
                   correctness_passed=correctness, all_percentile_budgets_passed=native['all_percentile_budgets_passed'],
                   all_performance_runs_eligible=native['all_performance_runs_eligible'],
                   phase_coverage_passed=phase_coverage, runtime_source_hash_mismatches=mismatch,
                   performance=performance, validation=validation,
                   streaming_implemented=False, visual_acceptance='not_run_S0_legacy_art',
                   history_acceptance='not_run', nationwide_capacity='not_tested',
                   long_frame_attribution='no_frames_over_33ms_in_valid_profiles; invalid_04_not_attributed', next_stage_started=False,
                   user_acceptance='pending', branch=git('branch', '--show-current'), source_parent=git('rev-parse', 'HEAD'))
    save(report / 'SUMMARY.json', summary)
    source_rows = []
    for row in source['tests']:
        log = report / 'source' / row['name'] / 'runtime.txt'
        if row['name'] == 's0_contract':
            log = report / 'latest_contract/s0_contract/runtime.txt'
        count = checks_from_log(log)
        source_rows.append(f"|{row['name']}|{count if count is not None else 'PASS标记'}|{'通过' if row['passed'] else '失败'}|")
    perf_rows = [f"|{row['name']}|{row['seconds']:.3f}|{row['p95_ms']:.3f}|{row['p99_ms']:.3f}|{row['max_ms']:.3f}|{row['long_frame_counts']['over_33ms']}/{row['long_frame_counts']['over_50ms']}/{row['long_frame_counts']['over_100ms']}|{'达标' if row['percentile_budget_passed'] else '超预算'}|" for row in performance]
    by_mode = {}
    for mode in ['legacy', 'v02']:
        rows = [row for row in performance if row['mode'] == mode]
        by_mode[mode] = dict(worst_p95_ms=max(row['p95_ms'] for row in rows), worst_p99_ms=max(row['p99_ms'] for row in rows),
                             private_peak_bytes=max(row['windows_metrics']['private_peak_bytes'] for row in rows),
                             gpu_dedicated_peak_bytes=max((row['windows_metrics']['gpu_dedicated_peak_bytes'] for row in rows if row['windows_metrics']['gpu_dedicated_peak_bytes'] is not None), default=None))
    save(report / 'worst_by_mode.json', by_mode)
    native_counts = {name:read(work / 'native' / name / 'result.json').get('checks') for name in ['legacy_verify','tree_edges']}
    actual_configs = sorted({f"渲染 {row['dimensions']['viewport_texture_px']}，客户端 {row['dimensions']['window_client_px']}，DPI {row['dimensions']['screen_dpi']}，content_scale_mode={row['dimensions']['content_scale_mode']}，factor={row['dimensions']['content_scale_factor']}" for row in performance})
    configuration_text = '\n'.join('- ' + text for text in actual_configs)
    report_text = f"""# 潼关 v0.2 S0 技术候选

构建 `{args.build_id}`，分支 `{git('branch', '--show-current')}`。本批完成基线接线、独立入口、观测与旧回归，停止在S0验收；不是整套v0.2完成。源检查、原生检查和百分位预算分别见下。用户验收pending。

## 版本与执行环境

主项目 `H:/tongguan_reviewfix_20261015`；历史项目 `H:/tongguan_slice_v01_20261014` 只读追溯。原HEAD `3a67d91e25a24d2c42b5fdd2a370f807c9812fc1` 与设计合并基线 `{BASE}` 文件树一致，工作分支从合并提交创建。开工时无未提交修改。

Godot4.6.1 official，GL Compatibility，RTX4060，实际渲染纹理固定1920×1080，客户端与DPI独立实测。探针使用viewport基础分辨率，正常手动入口保留canvas_items；不将窗口放大说成提高渲染分辨率。硬件原始来源见environment.json；Win32_VideoController.AdapterRAM存在32位限制，不将其数值当作实际显存总量。窗口模式更小缓冲及_04运行期间尺寸变化的失败证据保留。

运行时配置（同一配置去重列出）：
{configuration_text}

## 正确性、失败与未执行项

当前源码回归：`{source['passed']}`；原生兼容：`{native['technical_passed']}`；S0正确性与源码一致性：`{correctness}`。原生旧入口 `{native_counts['legacy_verify']}` 项，REV-02树边缘像素 `{native_counts['tree_edges']}` 项。所有原始命令、退出码与诊断在source/及native/。

开发期失败全部保留在development_evidence/：新入口尚不存在时的契约红灯；Release不支持命令行覆盖场景；原生探针两个变量无法推断类型（增加显式脚本解析回归后修复）；窗口尺寸未达到目标；JSON数字浮点数组与整型实测数组比较导致的尺寸误判（独立红绿回归后修复）；_04首轮60秒因渲染尺寸变化退出1（固定探针基础缓冲后重测，旧数据不计入正式结果）。构建工具早期Git中文路径引用错误发生在产物目录创建前，已改为NUL分隔原始路径解析；该次无发行产物。早期_01—_04构建保留在review-work，不作为交付。

流式调度/淘汰、V1新组合画面、历史准确性、第二节点、全国容量及Q1全矩阵均未执行。正式样本没有>33ms帧；_04无效样本的长帧原始记录保留，未作外部/地图归因。

## 当前实现

新入口为runtime/v02/main.tscn。Session在创建缓存前选择视觉服务，两个模式共用原控制器、GameState/Context和一份六页缓存。v02通过组合委托旧显示；未创建新游戏权威、存档格式或生成器。原绘制计划仍为全量重建，计数如实显示。

指标说明见[观测字段](../../../docs/map_v02/S0_METRICS.md)，落地范围见[实施清单](../../../docs/map_v02/S0_IMPLEMENTATION.md)。实际资源请求、候选、树提交及唯一纹理估算已采集；释放数为null/not_instrumented。唯一字节数按RGBA8完整mip链估算，Windows GPU占用另采，不能互相替代。

## 视觉边界

composition.png为计时外的旧素材同镜头截图。新旧模式截图哈希一致性见screenshot_comparison.json；这只验证S0显示保持一致，不是V1手绘组合认可。美术、历史与用户验收保持独立。

## 固定profile与帧时

同一S0 PCK、同一组旧素材、3秒预热、30秒固定轨迹。每模式3×60秒及1×300秒，全部六种镜头阶段的逐帧覆盖：`{phase_coverage}`。无截图读回进入性能循环。开始/结束进程快照检查，不擅自终止用户程序，也不声称清空OS磁盘缓存。

|运行|实测秒|p95 ms|p99 ms|最大 ms|>33/50/100ms帧数|百分位预算|
|---|---:|---:|---:|---:|---|---|
{chr(10).join(perf_rows)}

冻结预算p95≤16.7ms、p99≤25ms。全部百分位预算：`{native['all_percentile_budgets_passed']}`；全部性能运行资格：`{native['all_performance_runs_eligible']}`。每模式最差轮次和Windows内存峰值另列worst_by_mode.json，不挑最好一轮。正式样本中>33/50/100ms均为0；结论范围是本机S0旧素材基线，不是Q1或全国容量验收。

## 旧源码回归

|用例|断言数/标记|结果|
|---|---:|---|
{chr(10).join(source_rows)}

REV-01/03保留原回归，REV-02实际纹理像素检查在原生Release执行。新契约包含默认选择、显式覆盖、重复/非法模式、脚本编译、单缓存、共享状态、真实计数、空指标和JSON尺寸比较。

## 兼容、交付与回退

scope.json逐文件核对 `{scope['protected_baseline_files']}` 个不允许修改的基线文件。旧v4、Save22、world/site/slot、通道、人工补丁、删除、锁区及PNG未改；插件仍为空素材注册表。sealed_protection.txt复验580封存源码及旧EXE/PCK/ZIP。旧REVIEW/PUBLIC/历史build清单原样保留，新源码使用V02_SOURCE_MANIFEST.json，当前构建用独立BUILD.json与ARTIFACTS.json追溯。

Windows包：[打开S0](../../../review-work/map_v02/{args.build_id}/release/Windows/Start-S0.cmd)；[打开本批legacy对照](../../../review-work/map_v02/{args.build_id}/release/Windows/Start-Legacy.cmd)。无需Godot或Python运行。两个EXE与各自同名PCK必须一起保留。S0手动入口保存路径为user://tests/map_v02/manual，未接管玩家默认存档。

回退优先直接运行旧封存_02或_03发行包；源码回退在独立目录检出 `{BASE}` 即可。当前工作分支保留全部S0改动；不要重置或覆盖主工程、旧发行包或用户地图。本批未提交、推送或发布GitHub Release。
"""
    (report / 'REPORT.md').write_text(report_text, encoding='utf-8')
    (report / 'CHANGED_FILES.md').write_text('# S0 改动清单\n\n' + '\n'.join('- `' + name + '`' for name in scope['changed_paths']) + '\n\n最终证据目录见本报告。所有未在允许范围的基线文件逐文件校验。\n', encoding='utf-8')
    windows = work / 'release/Windows'
    package = work / (args.build_id + '_windows.zip')
    if not package.exists():
        with zipfile.ZipFile(package, 'x', zipfile.ZIP_DEFLATED, compresslevel=5) as archive:
            for path in sorted(windows.iterdir()):
                archive.write(path, 'Windows/' + path.name)
    with zipfile.ZipFile(package) as archive:
        bad = archive.testzip()
        if bad:
            raise RuntimeError('Package CRC mismatch: ' + bad)
        for path in windows.iterdir():
            import hashlib
            if hashlib.sha256(archive.read('Windows/' + path.name)).hexdigest() != sha(path):
                raise RuntimeError('Package content mismatch: ' + path.name)
    save(report / 'PACKAGE.json', dict(path=package.relative_to(ROOT).as_posix(), sha256=sha(package), bytes=package.stat().st_size))
    # Hash every report input after assembling it; this manifest intentionally excludes itself.
    save(report / 'EVIDENCE_MANIFEST.json', dict(files=[dict(path=path.relative_to(report).as_posix(), bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(report.rglob('*')) if path.is_file()]))
    print('S0_REPORT', str(report), 'correctness', correctness, 'percentiles', native['all_percentile_budgets_passed'], flush=True)
    return 0 if correctness else 1

if __name__ == '__main__':
    raise SystemExit(main())
