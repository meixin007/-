"""Untrimmed statistics and versioned, checksum-bound Windows activation pointers."""
import errno,hashlib,json,math,os,re
from pathlib import Path
import numpy as np

def frame_summary(values):
    a=np.asarray(values,dtype=float)
    if not a.size or not np.all(np.isfinite(a)) or np.any(a<=0):raise ValueError('invalid frame intervals')
    p95,p99=np.percentile(a,[95,99])
    return dict(frames=int(a.size),p50_ms=float(np.median(a)),p95_ms=float(p95),p99_ms=float(p99),max_ms=float(a.max()),over_33ms=int((a>33).sum()),over_50ms=int((a>50).sum()),over_100ms=int((a>100).sum()),budget_passed=bool(p95<=16.7 and p99<=25),outliers_removed=0)

def memory_summary(samples):
    private=[r['private_bytes'] for r in samples if r.get('private_bytes') is not None]
    gpu=[r['gpu_dedicated_bytes'] for r in samples if r.get('gpu_dedicated_bytes') is not None]
    return dict(private_peak_bytes=max(private,default=None),gpu_peak_bytes=max(gpu,default=None),gpu_samples=len(gpu),gpu_budget_verified=bool(gpu),private_budget_passed=bool(private) and max(private)<=4*1024**3,gpu_budget_passed=None if not gpu else max(gpu)<=int(1.5*1024**3))

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('w',encoding='utf-8') as f:json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
def version_root(root,version):
    if not re.fullmatch('[A-Za-z0-9_-]+',version):raise ValueError('unsafe version')
    return Path(root).resolve()/'versions'/version
def write_version(root,version,files):
    target=version_root(root,version);target.mkdir(parents=True,exist_ok=False);rows={}
    for name,data in files.items():
        p=(target/name).resolve()
        if not p.is_relative_to(target) or p==target:raise ValueError('unsafe file')
        p.parent.mkdir(parents=True,exist_ok=True)
        with p.open('xb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        rows[name]=digest(p)
    write_json(target/'complete.json',dict(version=version,files=rows));return target
def validate_version(root,version):
    target=version_root(root,version)
    if not (target/'complete.json').is_file():raise ValueError('incomplete version')
    value=json.loads((target/'complete.json').read_text(encoding='utf-8'))
    if value.get('version')!=version or not value.get('files'):raise ValueError('invalid completion')
    for name,expected in value['files'].items():
        path=(target/name).resolve()
        if not path.is_relative_to(target) or not path.is_file() or digest(path)!=expected:raise ValueError('bad version file '+name)
    return dict(version=version,manifest_sha256=digest(target/'complete.json'))
def activate(root,version,fault=None):
    root=Path(root);value=validate_version(root,version);path=root/'active.json';pending=root/'active.pending.json'
    if fault=='disk_full':raise OSError(errno.ENOSPC,'injected write boundary disk-full failure')
    write_json(pending,value)
    if fault=='before_replace':raise OSError(errno.EINTR,'injected interruption before Windows pointer replacement')
    if path.exists():
        prior=root/'previous.json';temp=root/'previous.pending.json'
        with temp.open('wb') as f:f.write(path.read_bytes());f.flush();os.fsync(f.fileno())
        os.replace(temp,prior)
    os.replace(pending,path)
    return value
def rollback(root):
    root=Path(root);prior=json.loads((root/'previous.json').read_text(encoding='utf-8'));validate_version(root,prior['version'])
    data=(root/'previous.json').read_bytes();temp=root/'rollback.pending.json'
    with temp.open('wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
    os.replace(temp,root/'active.json')
def activate_review(root,version,approved):
    if not approved:return dict(ok=False,code='style_migration_rejected')
    return dict(ok=True,active=activate(root,version))
