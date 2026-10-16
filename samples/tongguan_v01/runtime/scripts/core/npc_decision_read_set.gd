extends RefCounted
# The server reconstructs the observer's inputs. Domain services separately
# validate current funds, consent and object state when applying the choice.
const Pages = preload("res://scripts/core/npc_context_pages.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const ROOTS := ["actor_id", "day", "self_profile", "known_characters", "information_claims", "memories", "controlled_accounts", "own_tasks", "own_contracts", "own_authorizations", "recent_results", "employment_guidance", "public_work_guidance", "decision_guidance", "response_guidance", "purchase_guidance", "survival_guidance", "own_offices", "controlled_assets", "public_assets", "travel_destinations", "action_catalog", "paging", "projection_kind"]

# Only the engine records these controls, from its actual preview and page
# result. No prompt values, hidden world paths or model-supplied dependencies.
static func validate_manifest(manifest: Variant) -> Dictionary:
	if not manifest is Array or manifest.is_empty() or manifest.size() > 1 + Pages.MAX_PAGES: return {"ok": false, "error": "invalid NPC delivered input manifest"}
	var first: Variant = manifest[0]
	if not first is Dictionary or first.keys().size() != 2 or first.get("kind") != "preview" or typeof(first.get("page_size")) not in [TYPE_INT, TYPE_FLOAT]: return {"ok": false, "error": "invalid NPC delivered preview"}
	if not is_finite(float(first.page_size)) or first.page_size < 1 or first.page_size > 32 or floor(float(first.page_size)) != float(first.page_size) or int(first.page_size) not in [1, 2, 8, 32]: return {"ok": false, "error": "invalid NPC delivered preview width"}
	var seen: Array = []
	for descriptor in manifest.slice(1):
		if not descriptor is Dictionary or descriptor.get("kind") != "page": return {"ok": false, "error": "invalid NPC delivered page"}
		var fields: Array = ["kind", "path", "offset"] + (["query"] if descriptor.has("query") else [])
		if descriptor.size() != fields.size() or fields.any(func(field): return not descriptor.has(field)): return {"ok": false, "error": "invalid NPC delivered page fields"}
		var control: Dictionary = descriptor.duplicate(true)
		control["kind"] = "context_request"
		control["schema_version"] = 2
		control["snapshot_hash"] = "0".repeat(64)
		var checked: Dictionary = Pages.parse_request(control)
		if not checked.ok: return checked
		var signature: Dictionary = Canonical.hash_value(descriptor)
		if control.path[0] not in ROOTS or not signature.ok or signature.hash in seen: return {"ok": false, "error": "invalid or duplicate NPC delivered path"}
		seen.append(signature.hash)
	return {"ok": true}

static func page_descriptor(page: Dictionary) -> Dictionary:
	var descriptor := {"kind": "page", "path": page.path.duplicate(), "offset": page.offset}
	if page.has("query"): descriptor["query"] = page.query.duplicate(true)
	return descriptor

static func has_page(manifest: Array, page: Dictionary) -> bool:
	var wanted: Dictionary = Canonical.hash_value(page_descriptor(page))
	if not wanted.ok: return false
	for descriptor in manifest.slice(1):
		var digest: Dictionary = Canonical.hash_value(descriptor)
		if digest.ok and digest.hash == wanted.hash: return true
	return false

static func fingerprint(state, data: Dictionary, actor: String, manifest: Array = [], expected_page: Dictionary = {}) -> Dictionary:
	var projected: Dictionary = load("res://scripts/core/npc_decision_context_projection.gd").new().build(state, data, actor, 0, -1)
	if not projected.ok: return projected
	projected.context.erase("recent_failures")
	if manifest.is_empty(): return Canonical.hash_value({"manifest_version": 1, "observer": actor, "inputs": projected.context})
	var checked := validate_manifest(manifest)
	if not checked.ok: return checked
	projected.context["projection_kind"] = "npc_self_decision_v1"
	var pages := Pages.new()
	pages.source = projected.context
	pages.page_size = int(manifest[0].page_size)
	pages.priority_keys = Pages.build_priority(pages.source)
	pages.binding = {"actor_id": actor, "request_id": "read-set", "world_epoch": "read-set"}
	pages.snapshot_hash = "0".repeat(64)
	var inputs: Array = [Pages.preview(pages.source, [], false, pages.page_size, pages.priority_keys)]
	var expected_signature := "" if expected_page.is_empty() else str(Canonical.hash_value(page_descriptor(expected_page)).get("hash", ""))
	var expected_values := {}
	for descriptor in manifest.slice(1):
		var control: Dictionary = descriptor.duplicate(true)
		control["kind"] = "context_request"
		control["schema_version"] = 2
		control["snapshot_hash"] = pages.snapshot_hash
		var read: Dictionary = pages.read(control, actor, "read-set", "read-set")
		if not read.ok: return read
		read.page.erase("snapshot_hash")
		inputs.append(read.page)
		if not expected_signature.is_empty() and Canonical.hash_value(descriptor).get("hash") == expected_signature: expected_values = read.page
	if not expected_page.is_empty():
		var delivered := expected_page.duplicate(true)
		delivered.erase("snapshot_hash")
		var expected: Dictionary = Canonical.hash_value(delivered)
		var actual: Dictionary = Canonical.hash_value(expected_values)
		if expected_values.is_empty() or not expected.ok or not actual.ok or expected.hash != actual.hash: return {"ok": false, "error": "NPC delivered page changed; replan on current world"}
	# Own condition and changes to one's actual obligations/messages remain
	# decision triggers even when adaptive previews omit their detail. These
	# are observer-authorized projections, never other people's live records.
	var own_inputs := {}
	for key in ["self_profile", "survival_guidance", "controlled_accounts", "own_contracts", "own_authorizations", "own_tasks", "own_offices", "controlled_assets", "information_claims", "memories"]: own_inputs[key] = projected.context[key]
	return Canonical.hash_value({"manifest_version": 2, "observer": actor, "own_inputs": own_inputs, "inputs": inputs})
