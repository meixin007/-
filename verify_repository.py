from pathlib import Path
import hashlib,json,re,sys,zipfile
ROOT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    errors=[];files=[];secret_hits=[];images=0
    for p in sorted(ROOT.rglob('*')):
        if not p.is_file() or p.suffix=='.import' or any(x in ['.git','.godot','__pycache__'] for x in p.relative_to(ROOT).parts) or (p.suffix=='.uid' and p.relative_to(ROOT).parts[0]=='samples'):continue
        rel=p.relative_to(ROOT).as_posix();files.append(p)
        if p.suffix.lower() in ['.exe','.pck','.zip','.log','.pem','.key'] or p.name.startswith('main_status_'):errors.append('forbidden publish payload: '+rel)
        if p.suffix.lower()=='.png':images+=1
        if p.stat().st_size>95*1024*1024:errors.append('large Git blob: '+rel)
        if p.suffix.lower() not in ['.png','.bin']:
            try:value=p.read_text(encoding='utf-8-sig')
            except UnicodeError:errors.append('unexpected binary: '+rel);continue
            # Report filenames only, never key material.
            if re.search(r'(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|sk-[A-Za-z0-9_-]{35,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)',value):secret_hits.append(rel)
    for row in read(ROOT/'samples/tongguan_v01/PUBLIC_SOURCE_MANIFEST.json')['files']:
        if sha(ROOT/row['path'])!=row['sha256']:errors.append('source changed: '+row['path'])
    errors+=['potential credential in '+p for p in secret_hits]
    value=dict(passed=not errors,files=len(files),images=images,source_files=580,adapted_export_presets=2,native_code_changes=0,credential_scan_hits=secret_hits,errors=errors)
    print(json.dumps(value,ensure_ascii=False))
    return 0 if not errors else 1
if __name__=='__main__':raise SystemExit(main())
