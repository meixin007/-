class_name TangDnaExactRecord
extends RefCounted
## Optional exact envelope. Legacy genomes/JSON catalogs are never changed in place.
const Dna = preload("dna_core.gd")
const VERSION = "tang-dna-exact-1.0"
const MAX_BYTES: int = 65536

static func encode(dna: Dictionary, schema: Dictionary) -> Dictionary:
    var errors: Array = Dna.validate(dna,schema)
    if not errors.is_empty(): return _failure("invalid_dna",errors)
    if not dna.get("character_id") is String or str(dna["character_id"]).is_empty():
        return _failure("missing_dna_identity")
    var bytes: PackedByteArray = var_to_bytes(dna)
    if bytes.is_empty() or bytes.size()>MAX_BYTES: return _failure("payload_size_limit")
    var restored: Variant = bytes_to_var(bytes)
    if not restored is Dictionary or var_to_bytes(restored)!=bytes:
        return _failure("unsupported_variant_payload")
    var record: Dictionary = {
        "codec_version":VERSION,
        "engine_major":Engine.get_version_info()["major"],
        "dna_schema_version":dna["schema_version"],
        "dna_algorithm_version":dna["algorithm_version"],
        "character_id":dna["character_id"],
        "payload_format":"godot_variant_hex_objects_disabled",
        "payload_hex":bytes.hex_encode(),
        "payload_sha256":_digest(bytes),
    }
    return {"ok":true,"record":record}

static func decode(record: Dictionary, schema: Dictionary) -> Dictionary:
    if record.get("codec_version","")!=VERSION: return _failure("codec_version_mismatch")
    var engine: Variant = record.get("engine_major")
    if not (engine is int or engine is float) or not is_finite(float(engine)) or float(engine)!=float(Engine.get_version_info()["major"]):
        return _failure("engine_major_mismatch")
    if record.get("payload_format","")!="godot_variant_hex_objects_disabled":
        return _failure("payload_format_mismatch")
    if record.get("dna_schema_version","")!=schema.get("schema_version","") or record.get("dna_algorithm_version","")!=schema.get("algorithm_version",""):
        return _failure("dna_version_mismatch")
    var text: Variant = record.get("payload_hex")
    if not text is String or text.is_empty() or text.length()>MAX_BYTES*2 or text.length()%2!=0:
        return _failure("invalid_payload_hex")
    for index in range(text.length()):
        var code: int = text.unicode_at(index)
        if not ((code>=48 and code<=57) or (code>=97 and code<=102)):
            return _failure("invalid_payload_hex")
    var bytes: PackedByteArray = text.hex_decode()
    if _digest(bytes)!=record.get("payload_sha256",""): return _failure("payload_digest_mismatch")
    # Objects are never instantiated; Variant bytes are a bounded local data carrier.
    var decoded: Variant = bytes_to_var(bytes)
    if not decoded is Dictionary: return _failure("payload_not_dictionary")
    var errors: Array = Dna.validate(decoded,schema)
    if not errors.is_empty(): return _failure("invalid_dna",errors)
    if decoded.get("character_id","")!=record.get("character_id",""):
        return _failure("dna_identity_mismatch")
    if decoded.get("schema_version","")!=record["dna_schema_version"] or decoded.get("algorithm_version","")!=record["dna_algorithm_version"]:
        return _failure("dna_version_mismatch")
    if var_to_bytes(decoded)!=bytes: return _failure("noncanonical_variant_payload")
    return {"ok":true,"dna":decoded.duplicate(true)}

static func _digest(bytes: PackedByteArray) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(bytes)
    return context.finish().hex_encode()

static func _failure(reason: String, errors: Array = []) -> Dictionary:
    return {"ok":false,"reason":reason,"errors":errors}
