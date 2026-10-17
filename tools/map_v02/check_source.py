"""Fresh, non-overwriting source regression evidence for S0."""
from pathlib import Path
import argparse, json, os, re, subprocess, time

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get('GODOT_BIN', r'H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe')
CASES = [
    ('old_document', 'plugin-source', 'tests/test_document.gd', 'DOCUMENT_AND_ROUTE: PASS'),
    ('art_import', 'plugin-source', 'tests/test_art_import_feedback.gd', '"failures":[]'),
    ('geometry', 'samples/tongguan_v01/authoring', 'tests/test_review_geometry.gd', '"failures":[]'),
    ('ownership', 'samples/tongguan_v01/runtime', 'tests/test_review_ownership.gd', '"failures":[]'),
    ('publication', 'samples/tongguan_v01/runtime', 'tests/test_final_publication.gd', '"failures":[]'),
    ('view', 'samples/tongguan_v01/runtime', 'tests/test_r4_view.gd', '"failures":[]'),
    ('passage', 'samples/tongguan_v01/runtime', 'tests/test_r3_passage.gd', '"failures":[]'),
    ('construction', 'samples/tongguan_v01/runtime', 'tests/test_construction.gd', '"failures":[]'),
    ('save_migration', 'samples/tongguan_v01/runtime', 'tests/test_r5_saves.gd', '"failures":[]'),
    ('original_host', 'samples/tongguan_v01/runtime', 'tests/test_original_host.gd', '"failures":[]'),
    ('manual_layout', 'samples/tongguan_v01/authoring', 'tests/test_final_layout.gd', '"failures":[]'),
    ('authoring', 'samples/tongguan_v01/authoring', 'tests/test_r3_authoring.gd', '"failures":[]'),
    ('size_guard', 'samples/tongguan_v01/authoring', 'tests/test_r3_size_guard.gd', 'R3_SIZE_GUARD: PASS'),
    ('s0_contract', 'samples/tongguan_v01/runtime', 'tests/v02/test_s0_contract.gd', '"failures":[]'),
]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--only', choices=[row[0] for row in CASES])
    args = parser.parse_args()
    dest = Path(args.output).resolve()
    dest.mkdir(parents=True, exist_ok=False)
    results = []
    env = os.environ.copy()
    env['TONGGUAN_R5_FIXTURES'] = str(ROOT / 'samples/tongguan_v01/fixtures')
    for name, base, script, marker in CASES:
        if args.only and args.only != name:
            continue
        target = dest / name
        target.mkdir()
        command = [GODOT, '--headless', '--path', str(ROOT / base), '--script', 'res://' + script,
                   '--', '--report=' + str(target / 'details.json')]
        started = time.monotonic()
        try:
            process = subprocess.run(command, capture_output=True, timeout=160, env=env)
            raw = process.stdout + process.stderr
            (target / 'runtime.txt').write_bytes(raw)
            text = raw.decode('utf-8', errors='replace')
            diagnostics = re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$', text, re.M)
            row = dict(name=name, command=command, exit_code=process.returncode,
                       seconds=round(time.monotonic() - started, 3), diagnostics=diagnostics,
                       passed=process.returncode == 0 and not diagnostics and marker in text)
        except subprocess.TimeoutExpired as error:
            (target / 'runtime.txt').write_bytes((error.stdout or b'') + (error.stderr or b''))
            row = dict(name=name, command=command, passed=False, error='timeout', exit_code=None)
        (target / 'result.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
        results.append(row)
        print(name, row['passed'], row['exit_code'], flush=True)
    summary = dict(passed=all(row['passed'] for row in results), tests=results)
    (dest / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return 0 if summary['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
