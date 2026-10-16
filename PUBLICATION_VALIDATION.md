# 本次公开导出验证
2026-10-15，Windows / Godot4.6.1，上传目标meixin007/-。
14组新隔离副本检查均通过，未使用GitHub CI代替本机验证。

|检查|结果|耗时|
|---|---|---|
|plugin_allowlist|通过|0.094s|
|repository_scope|通过|0.422s|
|plugin_import|通过|4.516s|
|runtime_import|通过|5.343s|
|authoring_import|通过|4.141s|
|plugin_import_feedback|通过|1.016s|
|plugin_document|通过|0.953s|
|runtime_full_footprint|通过|3.437s|
|runtime_view|通过|3.344s|
|runtime_passage|通过|4.922s|
|runtime_construction|通过|5.094s|
|runtime_migration|通过|4.468s|
|authoring_layout|通过|9.922s|
|authoring_protection|通过|10.094s|

插件99个来源文件的SHA与当前主工程相符，插件仍为空注册表；样板来源580文件逐一校验，只有2个export_presets.cfg做了相对路径/本机标准导出模板适配，没有修改原生业务代码、美术或地理数据。
PNG和BIN样板资产在仓库，Windows EXE/PCK与原已测tongguan_v01_final_20261015_03产物SHA一致，文件值见RELEASE_ARTIFACTS.json。公开Windows ZIP重新打包为运行所需内容、说明及署名，未上传原机器Git状态或无关工作区历史，原本地封存ZIP未改变。
SHA256SUMS.txt随Release提供。PUBLIC_SOURCE_MANIFEST.json记录公开源码映射；Git关闭文本换行改写，以保持来源内容哈希。

原R5已测数值：制作163项/运行55项；60秒p95/p99 8.393/10.189ms；300秒8.452/9.752ms；20次进出连续采样未持续增长。原始数值摘要位于samples/tongguan_v01/validation，明确为原构建证据，非本次重测性能。
本次新检查不等于美术/精确历史/最终用户验收、Linux渲染或正式主工程部署。用户授权上传不自动改变R5候选状态。
