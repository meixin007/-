"""Publish the verified v0.2 snapshot without changing the development checkout or old releases."""
import argparse,datetime,hashlib,json,os,shutil,subprocess,sys,zipfile
from pathlib import Path
from common import ROOT,BASE,read,save,sha,scope_check

REPO='meixin007/-'
BUILD='tongguan_v02_q1_20261016_04'
BRANCH='codex/tongguan-v02-q1-20261017'
TAG='tongguan-v0.2-q1-20261017'
OUT=ROOT/'review-work/github_v02_20261017_01'
PUBLISH=OUT/'repository'

def command(args,cwd=ROOT,timeout=180):
    env=os.environ.copy();env.update(GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    p=subprocess.run(args,cwd=cwd,env=env,capture_output=True,timeout=timeout)
    text=(p.stdout+p.stderr).decode('utf-8',errors='replace')
    if p.returncode:raise RuntimeError('command failed '+str(args[:3])+'\n'+text)
    return text

def github(args,timeout=240):
    # Existing credential manager -> child environment only; never printed or persisted.
    env=os.environ.copy();env.update(GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    p=subprocess.run(['git','credential','fill'],cwd=ROOT,input='protocol=https\nhost=github.com\n\n',text=True,capture_output=True,env=env,timeout=25)
    fields=dict(line.split('=',1) for line in p.stdout.splitlines() if '=' in line)
    if p.returncode or not fields.get('password'):raise RuntimeError('GitHub credential unavailable')
    env['GH_TOKEN']=fields['password'];env['GH_HOST']='github.com'
    p=subprocess.run(['gh',*args],cwd=PUBLISH,env=env,capture_output=True,timeout=timeout)
    value=(p.stdout+p.stderr).decode('utf-8',errors='replace')
    if p.returncode:raise RuntimeError('GitHub operation failed: '+str(args[:2])+'\n'+value)
    return value

def zip_files(path,files):
    if path.exists():raise RuntimeError('archive already exists '+str(path))
    with zipfile.ZipFile(path,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for source,name in files:z.write(source,name)
    with zipfile.ZipFile(path) as z:
        if z.testzip():raise RuntimeError('archive CRC failed')
    return dict(name=path.name,path=str(path),sha256=sha(path),bytes=path.stat().st_size,crc_passed=True)

def prepare():
    OUT.mkdir(exist_ok=False);assets=OUT/'assets';assets.mkdir()
    work=ROOT/'review-work/map_v02'/BUILD;report=ROOT/'reports/map_v02'/BUILD
    delivery=read(report/'DELIVERY.json')
    if sha(delivery['path'])!=delivery['sha256']:raise AssertionError('measured release changed')
    for row in read(report/'DELIVERY_MANIFEST.json')['files']:
        if sha(report/row['path'])!=row['sha256']:raise AssertionError('sealed evidence changed '+row['path'])
    before=read(ROOT/'review-work/map_v02/q1_boundary/before.json')['files']
    if any(sha(ROOT/r['path'])!=r['sha256'] for r in before):raise AssertionError('pre-Q1 source changed')
    windows=assets/'Tongguan-v0.2-Q1-Windows-x64.zip';shutil.copyfile(delivery['path'],windows)
    rows=[dict(name=windows.name,path=str(windows),sha256=sha(windows),bytes=windows.stat().st_size,scope='Exact Q1 measured and clean-extracted Windows package')]
    stage=work/'SOURCE_RUNTIME'
    # Texture .import settings and script UIDs are metadata, not imported .godot cache.
    source=[f for f in sorted(stage.rglob('*')) if f.is_file() and not any(p in {'.godot','__pycache__','exports'} for p in f.relative_to(stage).parts)]
    source_manifest=assets/'EDITABLE_SOURCE_MANIFEST.json';save(source_manifest,dict(build_id=BUILD,files=[dict(path=f.relative_to(stage).as_posix(),sha256=sha(f),bytes=f.stat().st_size) for f in source],cache_excluded=True,texture_import_settings_preserved=True))
    source_archive=zip_files(assets/'Tongguan-v0.2-Q1-editable-Godot-project.zip',[(f,'GodotProject/'+f.relative_to(stage).as_posix()) for f in source]+[(source_manifest,'EDITABLE_SOURCE_MANIFEST.json')]);source_archive['scope']='Frozen measured Godot project, including generated presentation packages and import parameters; .godot cache excluded';rows.append(source_archive)
    rows.append(zip_files(assets/'Tongguan-v0.2-Q1-complete-evidence.zip',[(f,BUILD+'/'+f.relative_to(report).as_posix()) for f in sorted(report.rglob('*')) if f.is_file()]))
    movie_source=Path(delivery['external_evidence'][0]['path']);movie=assets/'Tongguan-v0.2-Q1-native-fixtures.avi';shutil.copyfile(movie_source,movie)
    if sha(movie)!=delivery['external_evidence'][0]['sha256']:raise AssertionError('movie changed')
    rows.append(dict(name=movie.name,path=str(movie),sha256=sha(movie),bytes=movie.stat().st_size,scope='Unedited 30fps MovieWriter supplementary visual evidence, excluded from performance measurements'))
    # Release checksums are portable; local filesystem paths stay out of this index.
    portable=[{k:v for k,v in row.items() if k!='path'} for row in rows]
    checksums=assets/'SHA256SUMS.txt';checksums.write_text(''.join(r['sha256']+'  '+r['name']+'\n' for r in rows),encoding='utf-8')
    release_manifest=assets/'RELEASE_MANIFEST.json';save(release_manifest,dict(build_id=BUILD,tag=TAG,repository=REPO,assets=portable,original_windows_zip_sha256=delivery['sha256'],gates=read(report/'ACCEPTANCE.json')))
    save(OUT/'assets.json',dict(assets=rows,extra_assets=[str(checksums),str(release_manifest)]))
    print('ASSETS_READY',len(rows),'bytes',sum(r['bytes'] for r in rows),flush=True)
    index=ROOT/'docs/map_v02/GITHUB_DELIVERY_20261017.md'
    text=f'''# 潼关地图 v0.2：源码、运行包与验收证据

v0.2的S0/V1/E1/E2/E3/V2/C1/Q1已完成。C1由用户通过，Q1包含35项矩阵、19组保护回归、本机实际1080p三次60秒和一次300秒压力测试。最差p95为2.853ms、p99为3.26467ms，正常稳态没有超过33ms的帧。

## 下载并运行

[v0.2 Q1 Release](https://github.com/{REPO}/releases/tag/{TAG})提供：

- `Tongguan-v0.2-Q1-Windows-x64.zip`：完整解压后运行`Start-Q1.cmd`。EXE与PCK保持同目录；不需要编辑器。
- `Tongguan-v0.2-Q1-editable-Godot-project.zip`：完整解压，以Godot4.6.1打开`GodotProject/project.godot`，入口`v02/q1/main.tscn`。冻结的表现包、纹理导入参数和脚本UID均包含，`.godot`缓存排除；无需依赖开发机器的`review-work`目录。
- `Tongguan-v0.2-Q1-complete-evidence.zip`：完整封存Q1报告，包括Git忽略的原始日志与无损压缩的重复大回执。对照其中`DELIVERY_MANIFEST.json`可验证每个成员。
- `Tongguan-v0.2-Q1-native-fixtures.avi`：未剪辑的工程夹具、故障回退与阈值切换录像。固定30fps，与正式不限帧性能统计分开。
- `SHA256SUMS.txt`及`RELEASE_MANIFEST.json`：下载产物校验。

## 操作与报告

1—4切换组合、院落、区域和远景；滚轮缩放，拖动平移。U/R卸载与重载，C/B建设前与开工，D一天，X/F损毁与修复，H/J成长与关门，G/T分页线与地形独显。5/N为工程夹具与下一片，Tab/K为工程势力与归属颜色。

[系统设计](01_系统设计文档_v0.2.md) · [批次说明](02_实施批次与首条开发任务_v0.2.md) · [Q1报告](../../reports/map_v02/{BUILD}/REPORT.md) · [验收矩阵](../../reports/map_v02/{BUILD}/ACCEPTANCE_MATRIX.json) · [最终本地包校验](../../reports/map_v02/{BUILD}/DELIVERY.json)

开发机报告中的绝对路径作为原始证据保留。跨机器阅读请使用本页的Release与相对源码链接；完整可编辑项目从上述源工程ZIP打开，仓库原默认入口继续保留旧版本。源码构建脚本在`tools/map_v02/`，包协议在`schemas/map_v02/`。

## 已验证范围

视觉继承用户认可C1；工程、兼容保护、实际释放重载、本机1080p性能及本地发布回退通过。1939个开工前文件不变，没有覆盖旧地图、素材或旧发行；未生成新AI美术，未量产内容。旧内容A/B兼容适配有额外开销，未宣称提速。

精确756年历史复原、全国容量与内容生产、第二真实地理节点、主工程默认入口接入均不属于本次完成声明。现代地形/水域来源及东亚粗示意保留原范围；Godot与素材授权见仓库来源说明及发行包内的通知。

| 发行文件 | 字节 | SHA256 |
|---|---:|---|
'''+''.join('| '+r['name']+' | '+str(r['bytes'])+' | `'+r['sha256']+'` |\n' for r in rows)
    index.write_text(text,encoding='utf-8')
    command(['git','clone','--no-hardlinks','--no-checkout',str(ROOT),str(PUBLISH)],timeout=180)
    command(['git','config','core.autocrlf','false'],PUBLISH)
    command(['git','remote','set-url','origin','https://github.com/'+REPO+'.git'],PUBLISH)
    command(['git','switch','-c',BRANCH,BASE],PUBLISH)
    source()

def source():
    before=read(ROOT/'review-work/map_v02/q1_boundary/before.json')['files']
    for name in ['user.name','user.email']:
        command(['git','config',name,command(['git','config','--get',name]).strip()],PUBLISH)
    names=command(['git','ls-files','--cached','--others','--exclude-standard','-z']).split('\0')
    bindings=[]
    for name in sorted(set(filter(None,names))):
        f=ROOT/name;target=PUBLISH/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target);bindings.append(dict(path=name,sha256=sha(f)))
    for script in ['verify_repository.py','plugin-source/verify_source.py']:
        output=command([sys.executable,script],PUBLISH,timeout=180);(OUT/(Path(script).stem+'.txt')).write_text(output,encoding='utf-8')
    scope=scope_check();save(OUT/'scope.json',scope)
    if not scope['passed']:raise AssertionError(scope['errors'])
    command(['git','add','--all'],PUBLISH)
    # Raw receipts retain their exact CR bytes and Markdown keeps intentional hard breaks.
    whole=subprocess.run(['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--cached','--check'],cwd=PUBLISH,capture_output=True)
    (OUT/'whole_payload_whitespace.txt').write_bytes(whole.stdout+whole.stderr)
    save(OUT/'whitespace_scope.json',dict(whole_payload_exit_code=whole.returncode,whole_payload_diagnostics='retained; raw logs and Markdown hard breaks are not normalized',source_scope=['samples/tongguan_v01/runtime','samples/tongguan_v01/authoring','tools/map_v02','schemas/map_v02']))
    command(['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--cached','--check','--','samples/tongguan_v01/runtime','samples/tongguan_v01/authoring','tools/map_v02','schemas/map_v02'],PUBLISH)
    if any(sha(ROOT/r['path'])!=r['sha256'] or sha(PUBLISH/r['path'])!=r['sha256'] for r in bindings):raise AssertionError('copy binding mismatch')
    save(OUT/'source_bindings.json',dict(files=bindings,source_checkout_preserved=True))
    command(['git','commit','-m','feat: deliver Tongguan v0.2 streaming map and verified Q1 release'],PUBLISH,timeout=180)
    commit=command(['git','rev-parse','HEAD'],PUBLISH).strip();tree=command(['git','rev-parse','HEAD^{tree}'],PUBLISH).strip()
    save(OUT/'prepared.json',dict(repository=REPO,base=BASE,branch=BRANCH,tag=TAG,commit=commit,tree=tree,payload_files=len(bindings),old_files_unchanged=len(before),prepared_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
    print('SOURCE_PREPARED',commit,'files',len(bindings),flush=True)

def push():
    prepared=read(OUT/'prepared.json')
    current=command(['git','ls-remote','origin','refs/heads/main'],PUBLISH).split()[0]
    if current!=BASE:raise RuntimeError('main changed; inspect before publishing')
    output=command(['git','push','--set-upstream','origin','HEAD:refs/heads/'+BRANCH],PUBLISH,timeout=900)
    (OUT/'push.txt').write_text(output,encoding='utf-8')
    remote=command(['git','ls-remote','origin','refs/heads/'+BRANCH],PUBLISH).split()[0]
    if remote!=prepared['commit']:raise AssertionError('remote head mismatch')
    save(OUT/'pushed.json',dict(passed=True,commit=remote,branch=BRANCH));print('GITHUB_PUSHED',remote,flush=True)

def release():
    prepared=read(OUT/'prepared.json');assets=read(OUT/'assets.json')
    body=OUT/'release_body.md';body.write_text(f'''潼关地图 v0.2 已完成 S0—Q1。用户已通过C1视觉审阅；Q1工程、兼容保护、本机1080p性能与发布回退通过。

正常负载3×60秒＋300秒：最差p95 2.853ms、p99 3.26467ms，312775个稳态间隔无>33ms帧；进程专用显存峰164.75MiB。20轮真实释放/重载，1939个开工前文件未变。

Windows包与正式测量及最终解压smoke的EXE/PCK字节一致。完整解压后启动Start-Q1.cmd。可编辑项目ZIP含完整Godot4.6.1项目、表现包和纹理导入参数，排除.godot缓存。证据ZIP含完整报告和原始数据；AVI为独立固定30fps的未剪辑补充录像，不用于性能统计。所有下载项以SHA256SUMS.txt验证。

来源与范围：现代DSM/岸线、东亚粗示意保留原说明，精确756历史复原和全国容量未签署。旧内容兼容A/B有额外开销，未宣称提速。没有覆盖旧图/素材、没有量产或回写主工程。旧Release保留。

[源码与操作说明](https://github.com/{REPO}/blob/{BRANCH}/docs/map_v02/GITHUB_DELIVERY_20261017.md) · [Q1报告](https://github.com/{REPO}/blob/{BRANCH}/reports/map_v02/{BUILD}/REPORT.md)
''',encoding='utf-8')
    # A fresh version/tag is used; existing release assets are never clobbered.
    raw=github(['api',f'repos/{REPO}/releases','--paginate']);existing=json.loads(raw)
    found=next((x for x in existing if x['tag_name']==TAG),None)
    if not found:
        print(github(['release','create',TAG,'--repo',REPO,'--target',prepared['commit'],'--title','潼关地图 v0.2：Q1 验证发行','--notes-file',str(body)]).strip(),flush=True)
    manifest=assets['assets'];paths=[row['path'] for row in manifest]+assets['extra_assets']
    current=json.loads(github(['api',f'repos/{REPO}/releases/tags/{TAG}']));names={x['name'] for x in current['assets']}
    for path in paths:
        if Path(path).name in names:continue
        print('UPLOADING_ASSET',Path(path).name,Path(path).stat().st_size,flush=True)
        github(['release','upload',TAG,path,'--repo',REPO],timeout=1800)
        print('UPLOADED_ASSET',Path(path).name,flush=True)
    current=json.loads(github(['api',f'repos/{REPO}/releases/tags/{TAG}']));by_name={x['name']:x for x in current['assets']}
    proofs=[]
    for row in manifest:
        asset=by_name.get(row['name'])
        if not asset or asset['size']!=row['bytes'] or asset.get('digest')!='sha256:'+row['sha256']:raise AssertionError('uploaded asset mismatch '+row['name'])
        proofs.append(dict(name=row['name'],bytes=asset['size'],digest=asset['digest'],url=asset['browser_download_url']))
    save(OUT/'release.json',dict(passed=True,url=current['html_url'],tag=TAG,target=prepared['commit'],assets=proofs,remote_digest_verified=True));print('RELEASE_VERIFIED',current['html_url'],flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('phase',choices=['prepare','source','push','release']);a=p.parse_args();globals()[a.phase]()
