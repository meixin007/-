"""S0 identity and evidence helpers. Never updates sealed manifests."""
from pathlib import Path
import hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = '62546a547895e1a6185904ad60bf15fa58c03244'
RUNTIME = ROOT / 'samples/tongguan_v01/runtime'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.quotePath=false', *args], cwd=ROOT).decode('utf-8').strip()

def source_files(base):
    return sorted(path for path in base.rglob('*') if path.is_file()
                  and not any(part in {'.godot', '__pycache__', 'releases'} for part in path.relative_to(base).parts)
                  and path.suffix not in {'.uid', '.import'} and path.name not in {'integration_result.json', 'build.json'})

def source_manifest():
    review = ROOT / 'samples/tongguan_v01/REVIEW_SOURCE_MANIFEST.json'
    files = [dict(path=path.relative_to(ROOT).as_posix(), sha256=sha(path), bytes=path.stat().st_size)
             for component in ['runtime', 'authoring']
             for path in source_files(ROOT / 'samples/tongguan_v01' / component)]
    value = dict(stage='S0', baseline_commit=BASE, actual_parent_commit=git('rev-parse', 'HEAD'),
                 review_manifest_sha256=sha(review), files=files)
    save(ROOT / 'samples/tongguan_v01/V02_SOURCE_MANIFEST.json', value)
    return value

def scope_check():
    scope = read(ROOT / 'schemas/map_v02/s0_scope.json')
    allowed = set(scope['modified_baseline_paths'])
    errors, protected = [], []
    tree = subprocess.check_output(['git', 'ls-tree', '-r', '-z', BASE], cwd=ROOT).decode('utf-8')
    for entry in filter(None, tree.split('\0')):
        info, name = entry.split('\t', 1)
        if name in allowed:
            continue
        path = ROOT / name
        expected = info.split()[2]
        data = path.read_bytes() if path.is_file() else b''
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()
        if not path.is_file() or actual != expected:
            errors.append('protected baseline changed: ' + name)
        else:
            protected.append(name)
    changed = set(filter(None, git('diff', '--name-only', BASE).splitlines()))
    changed.update(filter(None, git('ls-files', '--others', '--exclude-standard').splitlines()))
    for name in sorted(changed):
        if name in allowed or name in scope['new_exact_paths'] or any(name.startswith(prefix) for prefix in scope['new_path_prefixes']):
            continue
        errors.append('path outside S0 allowlist: ' + name)
    return dict(passed=not errors, baseline_commit=BASE, protected_baseline_files=len(protected),
                changed_paths=sorted(changed), errors=errors)
