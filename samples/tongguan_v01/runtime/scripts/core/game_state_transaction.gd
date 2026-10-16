extends RefCounted

class_name GameStateTransaction

const GameStateScript = preload("res://scripts/core/game_state.gd")
const CanonicalJSONScript = preload("res://scripts/core/canonical_json.gd")

const COMMAND_KINDS := [
	"character_birth",
	"character_appearance_style",
	"npc_decision",
	"assistant_conversation",
	"appoint_office", "transfer_office", "dismiss_office", "force_dismiss_office",
	"accountability_verdict", "governance_consult", "record_council_intervention",
	"select_council_clause", "revise_order", "withdraw_order", "finalize_council",
	"seal_governance_order", "event_verdict", "dialogue_consequence", "political_reaction",
	"regional_operation", "daily_settlement", "advance_time", "settle_task",
	"start_case_consultation", "publish_case_consultation", "submit_accountability_investigation", "select_political_season_route",
	"acknowledge_political_season_review", "resource_action", "assistant_binding", "assistant_advice", "family_office_terms", "management_plan", "management_task_control", "game_action", "employment_response", "audience_action", "emperor_coping"
]
const MAX_TRANSACTION_ID_LENGTH := 128
const MAX_COMMAND_PAYLOAD_LENGTH := 65536

func build_command_envelope(command_kind: String, input: Dictionary, preview_token: Dictionary = {}) -> Dictionary:
	var normalized_input := input.duplicate(true)
	var input_hash_result: Dictionary = CanonicalJSONScript.hash_value(normalized_input)
	var input_hash := str(input_hash_result.get("hash", ""))
	var transaction_id := _deterministic_transaction_id(command_kind, normalized_input, preview_token)
	return {
		"transaction_id": transaction_id,
		"kind": command_kind,
		"input": normalized_input,
		"input_hash": input_hash,
		"preview_token": preview_token.duplicate(true)
	}

func preview_command(state, command_kind: String, input: Dictionary, office_id: String = "", case_id: String = "") -> Dictionary:
	if not COMMAND_KINDS.has(command_kind):
		return _command_fail("unknown_command_kind", "unknown command kind")
	if state == null or not state.has_method("rule_payload_hash_without_revision"):
		return _command_fail("invalid_transaction_state", "state is invalid")
	var normalized_input := input.duplicate(true)
	var hash_result: Dictionary = CanonicalJSONScript.hash_value(normalized_input)
	if not bool(hash_result.get("ok", false)):
		return _command_fail("invalid_command_payload", "command payload is not canonical")
	if JSON.stringify(normalized_input).length() > MAX_COMMAND_PAYLOAD_LENGTH:
		return _command_fail("command_payload_too_large", "command payload is too large")
	var token := {
		"expected_state_revision": int(state.state_revision),
		"command_kind": command_kind,
		"command_input_hash": str(hash_result.get("hash", "")),
		"office_id": office_id,
		"case_id": case_id
	}
	return {"ok": true, "code": "preview_ready", "preview_token": token, "input_hash": str(hash_result.get("hash", "")), "state_revision": int(state.state_revision)}

func execute_command(context, envelope: Dictionary, operation: Callable) -> Dictionary:
	var envelope_validation := _validate_envelope(context, envelope, false)
	if not bool(envelope_validation.get("ok", false)):
		return envelope_validation
	var command_kind := str(envelope.get("kind", ""))
	var transaction_id := str(envelope.get("transaction_id", ""))
	var input_hash := str(envelope.get("input_hash", ""))
	var existing: Variant = context.state.processed_transactions.get(transaction_id, null)
	if existing != null:
		if not existing is Dictionary:
			return _command_fail("transaction_conflict", "existing transaction receipt is invalid")
		var receipt: Dictionary = existing
		if str(receipt.get("transaction_id", "")) != transaction_id or str(receipt.get("kind", "")) != command_kind or str(receipt.get("input_hash", "")) != input_hash:
			return _command_fail("transaction_conflict", "transaction id conflicts with an existing command")
		var replay_preview_validation := _validate_preview_token(context, envelope, true)
		if not bool(replay_preview_validation.get("ok", false)):
			return replay_preview_validation
		if str(receipt.get("status", "")) != "committed" or str(receipt.get("result_ref", "")).is_empty() or int(receipt.get("committed_revision", -1)) < 1 or int(receipt.get("committed_revision", -1)) > int(context.state.state_revision):
			return _command_fail("transaction_conflict", "existing transaction receipt is invalid")
		return {"ok": true, "code": "idempotent_replay", "result_ref": str(receipt.get("result_ref", "")), "receipt": receipt.duplicate(true), "state_revision": int(context.state.state_revision)}
	var preview_validation := _validate_preview_token(context, envelope)
	if not bool(preview_validation.get("ok", false)):
		return preview_validation
	var expected_transaction_id := _deterministic_transaction_id(command_kind, envelope.get("input", {}) as Dictionary, envelope.get("preview_token", {}))
	if transaction_id != expected_transaction_id:
		return _command_fail("transaction_id_mismatch", "transaction id does not match the command envelope")
	if not operation.is_valid():
		return _command_fail("invalid_operation", "command operation is invalid")
	var working = GameStateScript.new()
	var source_snapshot: Dictionary = context.state.to_transaction_dictionary()
	var loaded: Dictionary
	if context.has_method("_can_reuse_validated_state") and context._can_reuse_validated_state():
		# Only a sealed background context with an unchanged complete native
		# source can reuse the previous command's full validation. Normal roots,
		# restores, direct writes and expired bindings keep the strict loader.
		var previous_working_load_epoch: int = working.runtime_load_epoch
		working.load_dictionary(source_snapshot.persistent)
		working._restore_transaction_runtime(source_snapshot, previous_working_load_epoch)
		loaded = {"ok": true}
	else:
		loaded = working.load_transaction_dictionary(source_snapshot)
	if not bool(loaded.get("ok", false)):
		return _command_fail("transaction_snapshot_invalid", str(loaded.get("error", "transaction snapshot is invalid")))
	var working_context_result: Dictionary = context.with_state(working)
	if not bool(working_context_result.get("ok", false)):
		return _command_fail("transaction_context_invalid", str(working_context_result.get("error", "transaction context is invalid")))
	var operation_result: Variant = operation.call(working_context_result.get("context"))
	if not operation_result is Dictionary or not bool((operation_result as Dictionary).get("ok", false)):
		return _command_fail("command_failed", str((operation_result as Dictionary).get("error", "command failed")) if operation_result is Dictionary else "command failed")
	var result: Dictionary = (operation_result as Dictionary).duplicate(true)
	var before_rules: Dictionary = context.state.to_rule_state_dictionary()
	var after_rules: Dictionary = working.to_rule_state_dictionary()
	before_rules.erase("state_revision")
	after_rules.erase("state_revision")
	var comparison: Dictionary = CanonicalJSONScript.compare_values(before_rules, after_rules)
	if not comparison.ok:
		# Preserve the prior diagnostic payload and error order on rejection.
		# Only this failure path needs hashes; successful comparisons validate
		# both complete rule trees without constructing two full JSON strings.
		var before_validation: Dictionary = CanonicalJSONScript.validate_value(before_rules)
		var bad: Dictionary = CanonicalJSONScript.hash_value(context.state.to_dictionary() if not before_validation.ok else working.to_dictionary())
		return _command_fail("noncanonical_transaction_state", "原状态或执行结果无法计算规则校验值，未提交事务：" + str(bad.get("code", "")) + " " + str(bad.get("path", "")))
	if result.get("code", "") == "no_op" or comparison.equal:
		result["ok"] = true
		result["code"] = "no_op"
		result["state_revision"] = int(context.state.state_revision)
		return result
	working.state_revision = int(context.state.state_revision) + 1
	var result_ref := str(result.get("result_ref", "%s|%s" % [command_kind, transaction_id]))
	var receipt := {
		"transaction_id": transaction_id,
		"kind": command_kind,
		"input_hash": input_hash,
		"status": "committed",
		"result_ref": result_ref,
		"committed_revision": int(working.state_revision)
	}
	working.processed_transactions[transaction_id] = receipt.duplicate(true)
	var final_validation: Dictionary = working.try_load_dictionary(working.to_dictionary())
	if not bool(final_validation.get("ok", false)):
		return _command_fail("transaction_validation_failed", str(final_validation.get("error", "working state validation failed")))
	# The complete working state was validated immediately above, with no await
	# or external callback between validation and publication. Re-running every
	# domain validator on another copy adds no new evidence. Keep the strict
	# loader for untrusted snapshots and preserve independent mutable containers.
	var committed_snapshot: Dictionary = working.to_transaction_dictionary()
	var previous_load_epoch: int = context.state.runtime_load_epoch
	context.state.load_dictionary(committed_snapshot.persistent)
	context.state._restore_transaction_runtime(committed_snapshot, previous_load_epoch)
	if context.has_method("_note_fully_validated_state"): context._note_fully_validated_state()
	result["result_ref"] = result_ref
	result["receipt"] = receipt.duplicate(true)
	result["state_revision"] = int(context.state.state_revision)
	result["code"] = str(result.get("code", "committed"))
	return result

func _validate_envelope(context, envelope: Dictionary, validate_preview: bool = true) -> Dictionary:
	if context == null or context.state == null:
		return _command_fail("invalid_transaction_context", "context is invalid")
	var command_kind := str(envelope.get("kind", ""))
	if not COMMAND_KINDS.has(command_kind):
		return _command_fail("unknown_command_kind", "unknown command kind")
	var transaction_id := str(envelope.get("transaction_id", ""))
	if transaction_id.is_empty() or transaction_id.length() > MAX_TRANSACTION_ID_LENGTH or transaction_id.contains(" "):
		return _command_fail("invalid_transaction_id", "transaction id is invalid")
	var input: Variant = envelope.get("input", null)
	if not input is Dictionary:
		return _command_fail("invalid_command_payload", "command input is invalid")
	var hash_result: Dictionary = CanonicalJSONScript.hash_value(input)
	if not bool(hash_result.get("ok", false)) or JSON.stringify(input).length() > MAX_COMMAND_PAYLOAD_LENGTH:
		return _command_fail("invalid_command_payload", "command input is not canonical")
	if str(hash_result.get("hash", "")) != str(envelope.get("input_hash", "")):
		return _command_fail("command_input_hash_mismatch", "command input hash does not match")
	if validate_preview:
		return _validate_preview_token(context, envelope)
	return {"ok": true}

func _validate_preview_token(context, envelope: Dictionary, allow_stale: bool = false) -> Dictionary:
	var command_kind := str(envelope.get("kind", ""))
	var token: Variant = envelope.get("preview_token", {})
	if token != null and not token is Dictionary:
		return _command_fail("invalid_preview_token", "preview token is invalid")
	if not token is Dictionary or (token as Dictionary).is_empty():
		return _command_fail("missing_preview_token", "a fresh preview token is required")
	var preview: Dictionary = token
	if not allow_stale and int(preview.get("expected_state_revision", -1)) != int(context.state.state_revision):
		return _command_fail("stale_preview", "preview token is stale")
	if str(preview.get("command_kind", "")) != command_kind or str(preview.get("command_input_hash", "")) != str(envelope.get("input_hash", "")):
		return _command_fail("invalid_preview_token", "preview token does not match command")
	for key in ["office_id", "case_id"]:
		if not preview.has(key) or not (preview.get(key) is String):
			return _command_fail("invalid_preview_token", "preview token fields are invalid")
	return {"ok": true}

func _deterministic_transaction_id(command_kind: String, input: Dictionary, preview_token: Dictionary) -> String:
	if command_kind in ["npc_decision", "resource_action", "assistant_binding", "assistant_advice", "assistant_conversation", "management_plan", "management_task_control", "game_action", "employment_response", "audience_action", "emperor_coping"]:
		return "tx|%s|%s" % [command_kind, str(input.get("execution_id", "")).sha256_text().left(32)]
	var hash_result: Dictionary = CanonicalJSONScript.hash_value({"kind": command_kind, "input": input, "preview_token": preview_token})
	return "tx|%s|%s" % [command_kind, str(hash_result.get("hash", "")).left(32)]

func _command_fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}

func execute(context, operation: Callable) -> Dictionary:
	if context == null or context.state == null or not operation.is_valid(): return _fail("invalid_transaction")
	if not context.state.has_method("to_transaction_dictionary") or not context.state.has_method("load_transaction_dictionary"):
		return _fail("invalid_transaction_state")
	var working = GameStateScript.new()
	var loaded: Dictionary = working.load_transaction_dictionary(context.state.to_transaction_dictionary())
	if not bool(loaded.get("ok", false)): return loaded
	var working_result: Dictionary = context.with_state(working)
	if not bool(working_result.get("ok", false)): return working_result
	var working_context = working_result.get("context")
	var result: Variant = operation.call(working_context)
	if not (result is Dictionary) or not bool((result as Dictionary).get("ok", false)):
		return _fail(str((result as Dictionary).get("error", "transaction failed")) if result is Dictionary else "transaction failed")
	var committed: Dictionary = context.state.load_transaction_dictionary(working.to_transaction_dictionary())
	if not bool(committed.get("ok", false)): return committed
	if context.has_method("_note_fully_validated_state"): context._note_fully_validated_state()
	return (result as Dictionary).duplicate(true)

func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "game_state_transaction_failed", "error": message, "message": message}
