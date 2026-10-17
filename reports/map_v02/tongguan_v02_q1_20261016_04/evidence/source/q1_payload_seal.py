"""Preserve oversized duplicate result envelopes losslessly, then audit the final source view."""
import datetime,os,shutil,sys,zipfile
from common import ROOT,read,save,sha,scope_check
from v1_finalize import run

def main():
    build='tongguan_v02_q1_20261016_04';report=ROOT/'reports/map_v02'/build;work=ROOT/'review-work/map_v02'/build
    manifest=report/'DELIVERY_MANIFEST.json';original=read(manifest)
    for row in original['files']:
        if sha(report/row['path'])!=row['sha256']:raise AssertionError('pre-audit seal mismatch '+row['path'])
    prior=work/'initial_report_seal';prior.mkdir(exist_ok=False)
    for name in ['DELIVERY_MANIFEST.json','DELIVERY.json','REPORT.md']:shutil.copyfile(report/name,prior/name)
    large=[f for f in report.rglob('*.json') if f.stat().st_size>95*1024**2]
    if len(large)!=2 or any(f.name!='result.json' for f in large):raise AssertionError('unexpected oversized payload')
    archive=report/'evidence/raw_duplicate_results.zip';rows=[]
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for f in large:
            rel=f.relative_to(report).as_posix();rows.append(dict(path=rel,sha256=sha(f),bytes=f.stat().st_size));z.write(f,rel)
    with zipfile.ZipFile(archive) as z:
        if z.testzip():raise AssertionError('raw evidence CRC')
        import hashlib
        for row in rows:
            if hashlib.sha256(z.read(row['path'])).hexdigest()!=row['sha256']:raise AssertionError('raw evidence not lossless')
    for row in rows:
        f=report/row['path'];data=read(f);engine=data.pop('engine')
        data['engine_summary']={key:value for key,value in engine.items() if key not in ['observations','events']}
        data['raw_complete_result']=dict(archive=str(archive),member=row['path'],sha256=row['sha256'],uncompressed_bytes=row['bytes'],scope='The original unmodified JSON, including the embedded complete engine result. Adjacent engine_result.json also remains unmodified.')
        temporary=f.with_suffix('.pending.json');save(temporary,data);os.replace(temporary,f)
    save(report/'evidence/RAW_EVIDENCE.json',dict(passed=True,archive=str(archive),sha256=sha(archive),bytes=archive.stat().st_size,crc_passed=True,members=rows,reason='Two duplicate envelopes embed the same large engine event log; compressed losslessly to respect the Git source single-file limit. No event or frame discarded.'))
    text=(report/'REPORT.md').read_text(encoding='utf-8')
    text+='\n\n最终源码载荷复核：两份重复嵌入完整引擎事件的`result.json`超过95MiB，原始字节已无损封存于[evidence/raw_duplicate_results.zip](evidence/raw_duplicate_results.zip)，逐成员SHA/CRC见[RAW_EVIDENCE.json](evidence/RAW_EVIDENCE.json)。可读回执保留execution、budget和内存等字段，独立`engine_result.json`及全部CSV/JSONL未改动。最终ZIP仍保留原始完整回执；发行EXE/PCK与正式测量一致。\n'
    (report/'REPORT.md').write_text(text,encoding='utf-8')
    evidence=report/'evidence/final_source_audit';evidence.mkdir()
    run(evidence,'repository',[sys.executable,'tools/map_v02/q1_repository_check.py'])
    source=work/'repository_validation'
    for name in ['result.json','source_payload.txt']:shutil.copyfile(source/name,evidence/name)
    run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise AssertionError(scope['errors'])
    before=read(ROOT/'review-work/map_v02/q1_boundary/before.json')['files']
    if any(sha(ROOT/r['path'])!=r['sha256'] for r in before):raise AssertionError('old file changed')
    delivery=read(report/'DELIVERY.json')
    if sha(delivery['path'])!=delivery['sha256']:raise AssertionError('release ZIP changed')
    delivery['raw_duplicate_result_archive']=read(report/'evidence/RAW_EVIDENCE.json')
    delivery['final_source_payload_passed']=True;delivery['final_audit_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save(report/'DELIVERY.json',delivery)
    save(evidence/'audit_source.json',dict(script='tools/map_v02/q1_payload_seal.py',sha256=sha(ROOT/'tools/map_v02/q1_payload_seal.py'),initial_seal_preserved=str(prior/'DELIVERY_MANIFEST.json'),old_files_unchanged=len(before),passed=True))
    shutil.copyfile(ROOT/'tools/map_v02/q1_payload_seal.py',report/'evidence/source/q1_payload_seal.py')
    save(manifest,dict(build_id=build,files=[dict(path=f.relative_to(report).as_posix(),sha256=sha(f),bytes=f.stat().st_size) for f in sorted(report.rglob('*')) if f.is_file() and f.name!='DELIVERY_MANIFEST.json']))
    print('Q1_FINAL_SOURCE_AND_SEAL_PASS',len(before),'old files protected',flush=True)
if __name__=='__main__':main()
