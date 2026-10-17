"""Measure a new Release process; keep raw frames, log, dimensions and budgets."""
from pathlib import Path
import argparse, json, re, subprocess, sys, time
from common import ROOT, read, save, sha
sys.path.insert(0, str(ROOT / 'tools'))
from windows_process_monitor import Monitor

def inventory():
    command = ['powershell.exe', '-NoProfile', '-Command',
               "@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot|Tongguan' } | Select-Object ProcessId,Name,ExecutablePath,CommandLine) | ConvertTo-Json -Depth 3"]
    process = subprocess.run(command, capture_output=True, timeout=20)
    text = process.stdout.decode('utf-8-sig', errors='replace').strip()
    if process.returncode:
        return dict(available=False, exit_code=process.returncode)
    value = json.loads(text) if text else []
    return dict(available=True, processes=value if isinstance(value, list) else [value])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-id', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--mode', choices=['legacy', 'v02'], default='v02')
    parser.add_argument('--seconds', type=float, default=60)
    parser.add_argument('--default-selection', action='store_true')
    parser.add_argument('--legacy-check', choices=['verify', 'tree_edges'])
    args = parser.parse_args()
    release = ROOT / 'review-work/map_v02' / args.build_id / 'release'
    exe = release / ('Windows/TongguanLegacyS0.exe' if args.legacy_check else 'Windows/TongguanV02S0.exe')
    target = Path(args.output).resolve()
    allowed = (ROOT / 'review-work/map_v02').resolve()
    if not target.is_relative_to(allowed):
        raise ValueError('Evidence must be in review-work/map_v02')
    target.mkdir(parents=True, exist_ok=False)
    before = inventory()
    save(target / 'processes_before.json', before)
    report = target / 'result.json'
    command = [str(exe), '--resolution', '1920x1080', '--fullscreen',
               '--log-file', str(target / 'runtime.log')]
    command += ['--', '--expect-release', '--report=' + str(report)]
    if args.legacy_check:
        command += ['--acceptance', '--mode=' + args.legacy_check]
    else:
        command += ['--s0-probe', '--seconds=' + str(args.seconds),
                    '--evidence-root=' + str(target)]
        if not args.default_selection:
            command += ['--map-service=' + args.mode]
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=exe.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    monitor = Monitor(process.pid)
    samples, timed_out = [], False
    next_gpu = 0
    try:
        while process.poll() is None:
            elapsed = time.monotonic() - started
            if elapsed > (180 if args.legacy_check else args.seconds + 95):
                # Only this runner's owned child can be terminated.
                timed_out = True
                process.kill()
                break
            sample = monitor.memory()
            if sample:
                sample['elapsed_s'] = elapsed
                if elapsed >= next_gpu:
                    sample['gpu_dedicated_bytes'] = monitor.gpu()
                    next_gpu = elapsed + 1
                samples.append(sample)
            time.sleep(.1)
        process.wait(timeout=5)
    finally:
        monitor.close()
    after = inventory()
    save(target / 'processes_after.json', after)
    save(target / 'process_samples.json', samples)
    logfile = target / 'runtime.log'
    text = logfile.read_text(encoding='utf-8', errors='replace') if logfile.exists() else ''
    (target / 'runtime.txt').write_text(text, encoding='utf-8')
    diagnostics = re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$', text, re.M)
    result = read(report) if report.exists() else dict(failures=['no fresh native result'])
    gpu = [row['gpu_dedicated_bytes'] for row in samples if row.get('gpu_dedicated_bytes') is not None]
    contaminated = not before['available'] or not after['available'] or bool(before.get('processes')) or bool(after.get('processes'))
    execution = process.returncode == 0 and not timed_out and not diagnostics and not result.get('failures')
    if not args.legacy_check:
        execution = execution and result.get('mode') == args.mode
        stable_dimensions = all(row.get('dimensions') == result.get('dimensions') for row in result.get('periodic_observations', []))
        execution = execution and stable_dimensions
        result['all_periodic_dimensions_stable'] = stable_dimensions
    budget = None if args.legacy_check else (result.get('frame_p95_ms', 999) <= 16.7 and result.get('frame_p99_ms', 999) <= 25)
    result.update(command=command, process_exit_code=process.returncode, timed_out=timed_out, diagnostics=diagnostics,
                  process_id=process.pid, process_wall_seconds=time.monotonic() - started,
                  isolation=dict(start_and_end_inventory_available=before['available'] and after['available'],
                                 other_godot_or_tongguan_observed=contaminated,
                                 note='Start/end snapshots only; no claim of continuous OS process isolation; no user processes terminated.'),
                  windows_metrics=dict(private_peak_bytes=max((row['private_bytes'] for row in samples), default=None),
                                       gpu_dedicated_peak_bytes=max(gpu) if gpu else None, sampling_target_ms=100),
                  execution_passed=execution, percentile_budget_passed=budget,
                  expected_mode=args.mode, default_selection_tested=args.default_selection,
                  performance_acceptance_eligible=execution and not contaminated and not args.legacy_check and args.seconds in [60, 300],
                  artifact_hashes={path.name:sha(path) for path in (release / 'Windows').iterdir() if path.suffix in {'.exe', '.pck'}},
                  os_disk_cache_cleared=False)
    save(report, result)
    print('S0_NATIVE', args.legacy_check or args.mode, 'execution', execution, 'budget', budget,
          'p95', result.get('frame_p95_ms'), 'failures', result.get('failures'), 'diagnostics', diagnostics, flush=True)
    return 0 if execution else 1

if __name__ == '__main__':
    raise SystemExit(main())
