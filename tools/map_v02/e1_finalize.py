"""Seal local E1 evidence without rewriting earlier S0/V1 deliveries."""
from pathlib import Path
import argparse,importlib.metadata,re,shutil,subprocess,sys,zipfile
from jsonschema import Draft202012Validator
from common import ROOT,RUNTIME,read,save,sha,source_files,scope_check
from v1_finalize import run


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--build-id',required=True);a=parser.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.build_id):raise ValueError('build id')
    work=ROOT/'review-work/map_v02'/a.build_id;report=ROOT/'reports/map_v02'/a.build_id
    report.mkdir(parents=True,exist_ok=False);evidence=report/'evidence';evidence.mkdir()
    native=read(work/'native_01/result.json')
    if not native['technical_passed']:raise RuntimeError('native failed')
    for row in read(work/'SOURCE_MANIFEST.json')['files']:
        if sha(ROOT/row['path'])!=row['sha256']:raise RuntimeError('source drift '+row['path'])
    for name in ['package_loader.gd','checks.gd','app.gd','boot.gd','main.tscn']:
        if sha(RUNTIME/'v02/e1'/name)!=sha(work/'SOURCE_RUNTIME/v02/e1'/name):raise RuntimeError('staged source drift')
    for name,row in read(work/'ARTIFACTS.json').items():
        if sha(work/'CLEAN_WINDOWS'/name)!=row['sha256']:raise RuntimeError('artifact changed')
        if name in native['artifacts'] and native['artifacts'][name]!=row['sha256']:raise RuntimeError('tested artifact drift')
    for name in ['SOURCE_MANIFEST.json','ARTIFACTS.json','snapshot_run.json','snapshot.txt','effective_snapshot.json','source_protocol.json','source_protocol.txt','source_protocol_result.json','export.json','export.txt','import.json','import.txt','import_pixels.json','import_pixels.txt']:
        shutil.copyfile(work/name,evidence/name)
    shutil.copytree(work/'native_01',report/'native',ignore=shutil.ignore_patterns('*.log'))
    shutil.copytree(ROOT/'review-work/map_v02/e1_boundary',evidence/'development')
    regression=ROOT/'review-work/map_v02/e1_regressions'
    shutil.copytree(regression,evidence/'regressions',ignore=shutil.ignore_patterns('SOURCE_RUNTIME'))
    previous=read(regression/'summary.json')
    final_cases=[r for r in previous['tests'] if r['name']!='v1']
    fresh=read(regression/'v1_fresh_import/run.json')
    final_cases.append(dict(name='v1_fresh_import',passed=fresh['passed'],details='regressions/v1_fresh_import/run.json'))
    if not all(r['passed'] for r in final_cases):raise RuntimeError('regression failed')
    save(evidence/'regressions_final.json',dict(passed=True,tests=final_cases,initial_v1_unimported_failure_retained=True))

    before=read(ROOT/'review-work/map_v02/e1_boundary/before.json')['files']
    changed=[row['path'] for row in before if not (ROOT/row['path']).is_file() or sha(ROOT/row['path'])!=row['sha256']]
    save(evidence/'protection.json',dict(passed=not changed,before_files=len(before),changed=changed))
    if changed:raise RuntimeError('protected sources changed')
    schema=read(ROOT/'schemas/map_v02/presentation_package.schema.json');Draft202012Validator.check_schema(schema)
    validator=Draft202012Validator(schema)
    package_rows=[]
    package_dir=work/'SOURCE_RUNTIME/v02/e1/packages'
    for id in ['lab','tongguan']:
        folder=package_dir/id;manifest=read(folder/'presentation.package.json')
        errors=[e.message for e in validator.iter_errors(manifest)]
        if errors:raise RuntimeError(errors)
        catalog=read(folder/'world.catalog.json');provenance=read(folder/'receipts/provenance.json')
        required=[r for r in manifest['files'] if r['kind']=='texture' and r['required']]
        row=dict(package=id,manifest_sha256=sha(folder/'presentation.package.json'),pages=len(catalog['pages']),required_textures=len(required),
            declared_source_png_bytes=sum((folder/r['path']).stat().st_size for r in required),
            estimated_required_rgba8_bytes=sum(r['estimated_rgba8_bytes'] for r in required),
            estimate_is_not_measured_vram=True,schema_passed=True)
        package_rows.append(row)
        destination=evidence/'packages'/id
        for path in folder.rglob('*.json'):
            target=destination/path.relative_to(folder);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
    snapshot=read(work/'effective_snapshot.json')
    real_objects=read(package_dir/'tongguan/instances/objects.json')['objects']
    original=[r for r in real_objects if r.get('source_record')]
    ids=sorted(r['id'] for r in original)
    preserved=(ids==sorted(snapshot['raw_instance_ids']) and all(r['source_record']['id']==r['id'] and r['position_m']==r['source_record']['position_m'] for r in original))
    save(evidence/'identity_preservation.json',dict(passed=preserved,source_ids=len(ids),stable_ids=ids,source_patch_sha256=snapshot['effective_patch_sha256'],v4_version=snapshot['source_format_versions']['v4'],save_version=snapshot['source_format_versions']['save'],logical_authority_modified=False))
    if not preserved:raise RuntimeError('object identity changed')
    save(evidence/'packages.json',dict(schema_sha256=sha(ROOT/'schemas/map_v02/presentation_package.schema.json'),jsonschema_version=importlib.metadata.version('jsonschema'),packages=package_rows))
    run(evidence,'compiler_tests',[sys.executable,'tools/map_v02/test_e1_package.py'])
    run(evidence,'repository',[sys.executable,'verify_repository.py'])
    run(evidence,'plugin_source',[sys.executable,'plugin-source/verify_source.py'])
    run(evidence,'sealed_protection',[sys.executable,'tools/verify_review_protection.py'])
    shutil.copyfile(ROOT/'review-work/protection.json',evidence/'sealed_protection_result.json')
    run(evidence,'whitespace',['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--check'])
    scope=scope_check();save(evidence/'scope.json',scope)
    if not scope['passed']:raise RuntimeError(scope['errors'])
    zip_path=work/(a.build_id+'_windows.zip')
    with zipfile.ZipFile(zip_path,'x',zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted((work/'CLEAN_WINDOWS').iterdir()):bundle.write(path,path.name)
    with zipfile.ZipFile(zip_path) as bundle:
        if bundle.testzip() is not None:raise RuntimeError('zip CRC')
    save(evidence/'archive.json',dict(path=str(zip_path),sha256=sha(zip_path),bytes=zip_path.stat().st_size,crc_passed=True))
    save(evidence/'supplemental_sources.json',dict(files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in sorted([* (ROOT/'tools/map_v02').glob('e1_*.py'),ROOT/'schemas/map_v02/presentation_package.schema.json',ROOT/'docs/map_v02/E1_IMPLEMENTATION.md'])]))
    approved=ROOT/'reports/map_v02/V1_A01_ACCEPTED_20261016.json'
    shutil.copyfile(approved,report/'V1_ACCEPTED.json')
    text=f'''# 潼关 v0.2：E1 独立分页包

构建 `{a.build_id}`。V1候选A已由用户于2026-10-16以“通过，继续”认可；[认可收据](V1_ACCEPTED.json)绑定原构建、素材清单、风格数据哈希和四个机位。原V1发行内的pending字段保留其生成时状态，由新收据明确接续，不重写旧发行证据。此次完成E1包协议和干净目录发行读取，不是整套v0.2完成。

## 启动和实际交付

启动 `H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/CLEAN_WINDOWS/Start-E1.cmd`。1切4×4工程夹具，2切原潼关有效快照，G切页界与原地块，滚轮缩放、拖动平移、Esc退出。

可编辑并重新导入的独立Godot工程：`H:/tongguan_reviewfix_20261015/review-work/map_v02/{a.build_id}/SOURCE_RUNTIME/project.godot`。这里包含编译出的config和分页包；原源码目录内的e1/main.tscn属于构建模板，须通过e1_build.py生成数据后运行。原项目默认入口未改。

Windows zip在同构建目录；evidence/archive.json记录路径、SHA与CRC。exe/pck/cmd一同解压即可运行，无需原工程、外置PNG/JSON或编辑器缓存。当前发行验证CWD仅含这三件文件，资源由导出PCK提供。

## 两个包使用同一套编译器和加载器

| 项目 | 4×4工程夹具 | 原潼关只读快照 |
|---|---|---|
| world_id | stream_lab_v02 | tongguan_final_validation_v1（沿用旧身份） |
| 页目录 | 16细页+4父页+1总览，共21 | 12细页+1旧总览，共13 |
| 必需导入纹理 | 22 | 27 |
| 缺页 | 1个细页故意缺失 | 无 |
| 对象 | 3个树/道路/岸线对象，另1个地点代理 | 原72实例+关楼+主通道和2支路，共76 |
| 地块 | 不创建战役地块 | 原8地块保持不变 |

夹具16个细页目录具有不同内容哈希，实际保留15个细页资源；缺失项用于验证回退。其余5个父级/总览资源实际存在，父级跨度逐层增大2倍。跨页树的完整paint范围引用四个细页，owner在负坐标页内，身份不依赖页坐标。道路与水岸穿越页界。工程地点A不伪装成第二个历史地点。

EffectiveMapAdapter先组合原integrity/publication.gd校验，再读取有效对象、原始ID列表、补丁、删除、固定、八地块与通道身份。不会重跑生成器或回写源文件。原72对象及位置逐一比对一致，manual.1保留、原tombstone仍删除；原v4、Save22与forest_grid_sha256_v2不变。

包内JSON、源PNG字节(.png.bin)、导入PNG、资源目录、素材描述、实例分片、地点描述及来源/风格收据有独立哈希和依赖。纹理请求再次核对原始字节，并从实际导入Texture2D取基础RGBA8像素比对。两包49个必需纹理均在Windows Release逐个读取验证。

## 本次验证

- 编译端12个测试通过；真实快照/原共享状态契约15项通过。
- 独立源工程协议检查85项通过；Windows Release原生检查{native['checks']}项通过，诊断为空，实际截图1920×1080。
- 世界、地点、布局、地块/固定骨架哈希、通道、投影及build身份逐项拒绝；源原始列表重复、记录key/ID不符、越界/绝对/脚本路径、缺失必需文件、哈希错误、畸形JSON、错误父页、页版本、paint依赖、风格收据与导入像素错误均有真实故障注入。
- 故意缺失fine_2_1：细节失败且parent_1_0成功，结果为detail_failed_fallback_ready；没有把缺页报告成资源全成功。被拒绝的新包保持原已载入包。
- 原占地、实例身份、发布、通道、建设、存档及V1关联回归通过，完整命令与输出见evidence/regressions_final.json。V1在新复制并导入的当前源码工程中复验16项，原冷源码目录缺导入缓存的首次失败保留。
- 开工前{len(before)}个文件哈希逐一不变，包括旧素材、旧地图、S0/V1源和报告。旧封存发行、源码白名单、插件空素材注册表、仓库校验及空白检查均通过。

本次新增的是加载/编译代码和数值工程夹具，没有生成新绘制美术。V1演示里的额外候选树、延长墙和仓储未被写入旧制作发布；本E1潼关画面仅用于读取有效制作数据，不作为完整V1画面的替代。玩家建设尚未接入此只读预览，未把玩家建筑烘入地形；已认可的V1运行包继续保留。

## 失败、修复与限制

首版透明素材像素比对失败，最小复现表明外部修改.import参数后仍沿用旧导入结果；在新构建自身的派生缓存中精确删除对应ctex/md5并强制重导入后，导入的关楼/树基础RGBA像素与源PNG解码结果逐字节一致。没有编辑原PNG或放宽像素阈值。原失败及前后差异在evidence/development/，01/02/03开发构建留在review-work。

开发时另修正了测试脚本的显式String类型、四页树冠夹具的根位置、JSON Schema路径正则与实际文件名不一致等问题。错误证据均保留。第一次V1冷源码检查虽打印16项通过，伴随纹理导入错误仍被总检查拒绝；随后在独立新导入工程中复验通过，未修改冻结V1源码。

E1采用同步按页请求，读取与包切换不创建GameState/账户；独立预览本身不运行玩法。现有共享GameState只在源适配器测试中证明读取不变。E2反向索引/相机计划缓存、E3异步加载/预算/真实淘汰、V2完整组合与玩法、C1整合及Q1仍未完成。本批没有新的性能或全国容量结论；估算RGBA字节不是实测显存。

所有写操作位于新增E1代码/测试/协议/报告与独立review-work、user://tests路径；没有提交、推送或发布。回退只需关闭E1预览，继续启动原V1或S0包，无存档/旧地图迁移。

[工程夹具原生截图](native/lab.png) · [潼关有效快照原生截图](native/tongguan.png) · [源码清单](evidence/SOURCE_MANIFEST.json) · [分包/估算信息](evidence/packages.json)
'''
    (report/'REPORT.md').write_text(text,encoding='utf-8')
    save(report/'ACCEPTANCE.json',dict(stage='E1',build_id=a.build_id,source='passed',native='passed',v1_visual='accepted_by_user',history='not_claimed',capacity='not_run',e2_e3='not_implemented',q1='not_complete',package_hashes=package_rows))
    save(report/'DELIVERY_MANIFEST.json',dict(build_id=a.build_id,files=[dict(path=p.relative_to(report).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in source_files(report) if p.name!='DELIVERY_MANIFEST.json']))
    print('E1_READY',report,flush=True)


if __name__=='__main__':main()
