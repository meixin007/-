class_name StableNamedRng
extends RefCounted
## 只用于游戏外貌抽样，不用于安全用途。
## 每个语义路径独立派生；不读写 Godot 的全局随机数状态。

const DOMAIN: String = "tang-portrait-sha256-v1\n"
const TWO_POW_48: float = 281474976710656.0


static func unit(seed_text: String, parts: Array) -> float:
	var tokens: Array = [seed_text]
	tokens.append_array(parts)
	var payload: String = DOMAIN
	for part in tokens:
		var token: String = str(part)
		payload += str(token.length()) + ":" + token
	var digest: PackedByteArray = payload.sha256_buffer()
	var numerator: float = 0.0
	for i in range(6):
		numerator = numerator * 256.0 + float(digest[i])
	return numerator / TWO_POW_48


static func index(seed_text: String, parts: Array, count: int) -> int:
	assert(count > 0)
	return mini(int(unit(seed_text, parts) * count), count - 1)


static func centered(seed_text: String, parts: Array) -> float:
	var path_a: Array = parts.duplicate()
	var path_b: Array = parts.duplicate()
	path_a.append("a")
	path_b.append("b")
	return unit(seed_text, path_a) + unit(seed_text, path_b) - 1.0

