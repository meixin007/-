from pathlib import Path
import hashlib,json,re,sys,zipfile
ROOT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    errors=[];files=[];secret_hits=[];images=0
    for p in sorted(ROOT.rglob('*')):
        if not p.is_file() or p.suffix=='.import' or any(x in ['.git','.godot','__pycache__','review-work'] for x in p.relative_to(ROOT).parts) or (p.suffix=='.uid' and p.relative_to(ROOT).parts[0]=='samples'):continue
        rel=p.relative_to(ROOT).as_posix();files.append(p)
        if p.suffix.lower() in ['.exe','.pck','.zip','.log','.pem','.key'] or p.name.startswith('main_status_'):errors.append('forbidden publish payload: '+rel)
        if p.suffix.lower()=='.png':images+=1
        if p.stat().st_size>95*1024*1024:errors.append('large Git blob: '+rel)
        if p.suffix.lower() not in ['.png','.bin']:
            try:value=p.read_text(encoding='utf-8-sig')
            except UnicodeError:errors.append('unexpected binary: '+rel);continue
            # Report filenames only, never key material.
            if re.search(r'(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|sk-[A-Za-z0-9_-]{35,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)',value):secret_hits.append(rel)
    manifest=ROOT/'samples/tongguan_v01/REVIEW_SOURCE_MANIFEST.json'
    if not manifest.exists():manifest=ROOT/'samples/tongguan_v01/PUBLIC_SOURCE_MANIFEST.json'
    inventory=read(manifest)
    v02=ROOT/'samples/tongguan_v01/V02_SOURCE_MANIFEST.json'
    if v02.exists():
        scope=read(ROOT/'schemas/map_v02/s0_scope.json');current=read(v02)
        if current.get('review_manifest_sha256')!=sha(manifest):errors.append('v0.2 baseline manifest mismatch')
        indexed={row['path']:row for row in current['files']}
        old_paths={row['path'] for row in inventory['files']}
        for row in inventory['files']:
            new=indexed.get(row['path'])
            if new is None:errors.append('v0.2 removed baseline source: '+row['path']);continue
            if new['sha256']!=row['sha256'] and row['path'] not in scope['modified_baseline_paths']:errors.append('v0.2 changed protected source: '+row['path'])
        for name in indexed.keys()-old_paths:
            if not any(name.startswith(prefix) for prefix in scope['new_path_prefixes']):errors.append('v0.2 source outside allowlist: '+name)
        inventory=current
    for row in inventory['files']:
        if not (ROOT/row['path']).is_file() or sha(ROOT/row['path'])!=row['sha256']:errors.append('source changed: '+row['path'])
    v1=ROOT/'samples/tongguan_v01/runtime/v02/v1/manifest.json'
    if v1.exists():
        v1_data=read(v1)
        if v1_data.get('s0_manifest_sha256')!=sha(v02):errors.append('V1 S0 receipt changed')
        for row in v1_data['files']:
            if not row['path'].startswith('samples/tongguan_v01/runtime/v02/v1/'):errors.append('V1 path outside namespace: '+row['path']);continue
            if not (ROOT/row['path']).is_file() or sha(ROOT/row['path'])!=row['sha256']:errors.append('V1 source changed: '+row['path'])
    errors+=['potential credential in '+p for p in secret_hits]
    value=dict(passed=not errors,files=len(files),images=images,source_files=len(inventory['files']),adapted_export_presets=2,baseline_commit=inventory.get('baseline_commit','26a45be93e62fc56199ed42d98895926380383c5'),credential_scan_hits=secret_hits,errors=errors)
    print(json.dumps(value,ensure_ascii=False))
    return 0 if not errors else 1
if __name__=='__main__':raise SystemExit(main())
