extends RefCounted
## Stable, transparent scenario choices; never change the owner's budget ceiling.
const MODES={"conservative":{"name":"保守","capacity":0.8,"cost":0.9,"bad_debt":0.5,"waste":0.0},"balanced":{"name":"均衡","capacity":1.0,"cost":1.0,"bad_debt":1.0,"waste":0.0},"expansion":{"name":"扩张","capacity":1.2,"cost":1.1,"bad_debt":1.5,"waste":0.05}}
static func valid(value: Variant) -> bool:
	return value is String and MODES.has(value)

static func description(mode: String) -> String:
	return {"conservative":"保守：规模降至八成，单位投入降至九成，金融坏账比例减半。","balanced":"均衡：按正常规模、投入和风险经营。","expansion":"扩张：规模提高两成、单位投入提高一成；普通经营另计投入的5%周转损耗，金融坏账比例提高五成。"}.get(mode,"")

static func success_message(mode: String) -> String:
	return "经营方针已改为%s；原资金限额不变，下次结算使用新方针。" % MODES[mode].name
