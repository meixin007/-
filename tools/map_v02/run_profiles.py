"""Serial native S0 regressions and frozen A/B profiles, with retained failures."""
import argparse, subprocess, sys
from common import ROOT, read, save

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-id', required=True)
    args = parser.parse_args()
    source = ROOT / 'review-work/map_v02/source_final/summary.json'
    if not source.exists() or not read(source)['passed']:
        raise RuntimeError('Current source regressions must finish before native sampling.')
    contract = ROOT / 'review-work/map_v02/contract_final/summary.json'
    if not contract.exists() or not read(contract)['passed']:
        raise RuntimeError('Latest S0 contract regression must finish before native sampling.')
    destination = ROOT / 'review-work/map_v02' / args.build_id / 'native'
    destination.mkdir(parents=True, exist_ok=False)
    command_base = [sys.executable, str(ROOT / 'tools/map_v02/run_native.py'), '--build-id', args.build_id]
    rows = [('legacy_verify', ['--legacy-check', 'verify']), ('tree_edges', ['--legacy-check', 'tree_edges'])]
    for index, mode in enumerate(['legacy', 'v02', 'v02', 'legacy', 'legacy', 'v02']):
        rows.append((f'{index + 1:02}_{mode}_60s', ['--mode', mode, '--seconds', '60']))
    rows += [('07_legacy_300s', ['--mode', 'legacy', '--seconds', '300']),
             ('08_v02_300s', ['--mode', 'v02', '--seconds', '300'])]
    results = []
    for name, options in rows:
        command = command_base + ['--output', str(destination / name)] + options
        print('S0_BEGIN', name, flush=True)
        process = subprocess.run(command, cwd=ROOT)
        path = destination / name / 'result.json'
        value = read(path) if path.exists() else {}
        results.append(dict(name=name, command=command, runner_exit_code=process.returncode,
                            execution_passed=value.get('execution_passed', False),
                            percentile_budget_passed=value.get('percentile_budget_passed'),
                            performance_acceptance_eligible=value.get('performance_acceptance_eligible', False)))
        save(destination / 'progress.json', dict(build_id=args.build_id, results=results, complete=False))
        print('S0_DONE', name, 'execution', results[-1]['execution_passed'], flush=True)
        if process.returncode:
            print('S0_STOP functional failure; inspect retained result before continuing.', flush=True)
            return 1
    summary = dict(build_id=args.build_id, results=results, complete=True,
                   technical_passed=all(row['execution_passed'] for row in results),
                   all_percentile_budgets_passed=all(row['percentile_budget_passed'] is not False for row in results),
                   all_performance_runs_eligible=all(row['performance_acceptance_eligible'] for row in results if row['percentile_budget_passed'] is not None))
    save(destination / 'summary.json', summary)
    print('S0_NATIVE_SUITE', summary['technical_passed'], summary['all_percentile_budgets_passed'], flush=True)
    return 0 if summary['technical_passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
