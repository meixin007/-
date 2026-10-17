"""Build a fresh S0 Windows runtime in an isolated staging project."""
from pathlib import Path
import argparse, os, re, shutil, subprocess
from common import ROOT, BASE, RUNTIME, git, save, sha, source_files, source_manifest, scope_check

GODOT = os.environ.get('GODOT_BIN', r'H:\godot4.61\Godot_v4.6.1-stable_win64_console.exe')
TEMPLATE = Path(os.environ.get('GODOT_WINDOWS_TEMPLATE', r'H:\godot4.61\export_templates_extract\templates\windows_release_x86_64.exe'))

def run(dest, project, name, arguments):
    command = [GODOT, '--headless', '--path', str(project), *arguments]
    result = subprocess.run(command, capture_output=True, timeout=180)
    raw = result.stdout + result.stderr
    (dest / (name + '.txt')).write_bytes(raw)
    diagnostics = re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$', raw.decode('utf-8', errors='replace'), re.M)
    save(dest / (name + '.json'), dict(command=command, exit_code=result.returncode, diagnostics=diagnostics))
    if result.returncode or diagnostics:
        raise RuntimeError('Build check failed: ' + str(dest / (name + '.txt')))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-id', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', args.build_id):
        raise ValueError('Invalid build id')
    scope = scope_check()
    if not scope['passed']:
        raise RuntimeError(scope['errors'])
    dest = ROOT / 'review-work/map_v02' / args.build_id / 'release'
    dest.mkdir(parents=True, exist_ok=False)
    staging = dest / 'SOURCE_RUNTIME'
    staging.mkdir()
    manifest = source_manifest()
    rows = []
    for path in source_files(RUNTIME):
        target = staging / path.relative_to(RUNTIME)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        rows.append(dict(path=path.relative_to(RUNTIME).as_posix(), bytes=path.stat().st_size, sha256=sha(target)))
    identity = dict(build_id=args.build_id, stage='S0', design_baseline_commit=BASE,
                    actual_parent_commit=git('rev-parse', 'HEAD'), branch=git('branch', '--show-current'),
                    source_manifest_sha256=sha(ROOT / 'samples/tongguan_v01/V02_SOURCE_MANIFEST.json'),
                    source_files=rows, delegation='legacy', streaming_implemented=False,
                    visual_acceptance='pending_user_review', release=True)
    save(staging / 'v02/build.json', identity)
    # The same old entry remains the default; S0 uses an explicit scene path.
    run(dest, staging, 'import', ['--editor', '--quit'])
    for path in (staging / 'bundle').rglob('*.png.import'):
        text = path.read_text(encoding='utf-8')
        path.write_text(text.replace('mipmaps/generate=false', 'mipmaps/generate=true'), encoding='utf-8')
    run(dest, staging, 'import_mips', ['--editor', '--quit'])
    export = staging / 'export_presets.cfg'
    text = export.read_text(encoding='utf-8').replace('custom_template/release=""', 'custom_template/release="' + TEMPLATE.as_posix() + '"')
    export.write_text(text, encoding='utf-8')
    windows = dest / 'Windows'
    windows.mkdir()
    run(dest, staging, 'export_legacy', ['--export-release', 'R5 Final', str(windows / 'TongguanLegacyS0.exe')])
    project = staging / 'project.godot'
    original_project = project.read_bytes()
    try:
        project.write_text(original_project.decode('utf-8').replace('run/main_scene="res://main.tscn"', 'run/main_scene="res://v02/main.tscn"'), encoding='utf-8')
        run(dest, staging, 'export_s0', ['--export-release', 'R5 Final', str(windows / 'TongguanV02S0.exe')])
    finally:
        project.write_bytes(original_project)
    (windows / 'Start-S0.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanV02S0.exe"\n', encoding='ascii')
    (windows / 'Start-Legacy.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "TongguanLegacyS0.exe"\n', encoding='ascii')
    save(dest / 'BUILD.json', identity)
    save(dest / 'ARTIFACTS.json', {path.name:dict(bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(windows.iterdir())})
    save(dest / 'scope_at_build.json', scope)
    print('S0_BUILD', args.build_id, len(rows), str(windows), flush=True)

if __name__ == '__main__':
    main()
