import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent
allowed = {'.gd', '.gdshader', '.uid', '.cfg', '.godot', '.tscn', '.md', '.py'}
registry = 'addons/strategic_map_editor/art/tongguan_v1/'
json_paths = {registry + 'catalog.json', registry + 'manifest.json', 'addons/strategic_map_editor/art_samples.json', 'examples/blank.map.json', 'SOURCE_EXPORT.json', 'VALIDATION.json'}
errors = []
count = 0
for path in sorted(root.rglob('*')):
    if not path.is_file() or any(part in {'.godot', '.git', '__pycache__'} for part in path.relative_to(root).parts):
        continue
    relative = path.relative_to(root).as_posix()
    count += 1
    if path.suffix not in allowed and relative not in json_paths:
        errors.append('File outside source allowlist: ' + relative)
    if '/art/' in '/' + relative and relative not in {registry + 'catalog.json', registry + 'manifest.json'}:
        errors.append('Art payload is forbidden: ' + relative)
    try:
        content = path.read_text(encoding='utf-8')
    except UnicodeError:
        errors.append('Non-UTF8 payload: ' + relative)
        continue
    if path.suffix == '.gd':
        for dependency in re.findall(r'preload\(\s*"([^"\n]+)"\s*\)', content):
            dependency_path = root / dependency[6:] if dependency.startswith('res://') else path.parent / dependency
            if not dependency_path.is_file():
                errors.append('Missing preload: ' + relative + ' -> ' + dependency)
for name, empty in [('catalog.json', {}), ('manifest.json', [])]:
    value = json.loads((root / registry / name).read_text(encoding='utf-8'))
    if value != {'version': 1, 'bundle_id': 'tongguan_v1', 'assets': empty}:
        errors.append('Registry must remain the generated empty configuration: ' + name)
blank = json.loads((root / 'examples/blank.map.json').read_text(encoding='utf-8'))
if blank['features'] or blank['presentation']['instances'] or blank['reference']['path'] or blank['reference_tiles']:
    errors.append('Blank example must not contain user data or art references')
print(json.dumps({'files': count, 'art_assets': 0 if not errors else None, 'errors': errors}, ensure_ascii=False))
raise SystemExit(1 if errors else 0)
