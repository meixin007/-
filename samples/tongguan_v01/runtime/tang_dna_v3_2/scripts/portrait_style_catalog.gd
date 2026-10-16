extends RefCounted
## Candidate slots are cosmetic presentation, never equipment or rank entitlements.
const KEYS = ["hair_asset_id","robe_asset_id","beard_asset_id"]
static func resolve(family: String, style: Variant, catalog: Dictionary) -> Dictionary:
    if family not in ["male","female"] or not style is Dictionary or style.size()>3:
        return _fail("invalid_portrait_style")
    if not catalog.get("families") is Dictionary or not catalog.families.get(family) is Dictionary:
        return _fail("missing_style_family")
    var spec: Dictionary = catalog.families[family]
    var selected: Dictionary = {}
    for key in style:
        if key not in KEYS or not style[key] is String or style[key].length()>128:
            return _fail("invalid_portrait_style")
    for key in KEYS:
        var id: String = str(style.get(key,""))
        if id.is_empty(): continue
        var slot: String = key.trim_suffix("_asset_id")
        if not spec.get(slot) is Dictionary or not spec[slot].has(id): return _fail("unavailable_"+slot+"_style")
        var frame: Variant = spec[slot][id]
        if not frame is Dictionary or not frame.get("path") is String or str(frame.path).is_empty() or not frame.get("cell") is Array or frame.cell.size()!=4:
            return _fail("invalid_style_frame")
        for value in frame.cell:
            if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0.0 or float(value)>1.0:
                return _fail("invalid_style_cell")
        if float(frame.cell[2])<=0.0 or float(frame.cell[3])<=0.0 or float(frame.cell[0])+float(frame.cell[2])>1.0 or float(frame.cell[1])+float(frame.cell[3])>1.0:
            return _fail("invalid_style_cell")
        selected[slot]=frame.duplicate(true)
        selected[slot]["id"]=id
        for transform_key in ["origin","scale"]:
            var pair: Variant = frame.get(transform_key,[0.0,0.0] if transform_key=="origin" else [1.0,1.0])
            if not pair is Array or pair.size()!=2: return _fail("invalid_style_transform")
            for value in pair:
                if not (value is int or value is float) or not is_finite(float(value)) or (transform_key=="scale" and (float(value)<=0.0 or float(value)>2.0)):
                    return _fail("invalid_style_transform")
            selected[slot][transform_key]=pair.duplicate()
    return {"ok":true,"selected":selected}
static func _fail(reason: String) -> Dictionary:
    return {"ok":false,"reason":reason,"complete":false}
