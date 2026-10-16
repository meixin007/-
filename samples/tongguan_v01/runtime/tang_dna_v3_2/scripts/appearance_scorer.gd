class_name TangAppearanceScorer
extends RefCounted
## Illustrative TEST scoring only. It does not validate real human attractiveness.
## No hard class assignment is applied to inherited children.
const WEIGHTS: Dictionary = {"eyes": 30.0, "nose": 20.0, "mouth": 15.0, "brows": 10.0, "bone": 15.0, "harmony": 10.0}


static func evaluate(groups: Dictionary) -> Dictionary:
    var eye: float = (float(groups["eyes"]["eye_length"]) + float(groups["eyes"]["eye_openness"])) * 0.5
    var nose: float = float(groups["nose"]["nose_length"])
    var mouth: float = (float(groups["mouth"]["mouth_width"]) + float(groups["mouth"]["cupid_bow"])) * 0.5
    var brows: float = float(groups["brows"]["brow_length"])
    var bone: float = 1.0 - absf(float(groups["bone"]["face_length"]) - float(groups["bone"]["face_width"]))
    # Component cross-relations, not a random 0..10 roll.
    var relation_penalty: float = (
        absf(float(groups["eyes"]["eye_spacing"]) - float(groups["bone"]["face_width"]))
        + absf(float(groups["nose"]["nostril_width"]) - float(groups["mouth"]["mouth_width"]))
        + absf(float(groups["bone"]["chin_length"]) - float(groups["mouth"]["philtrum_length"]))
    ) / 3.0
    var harmony: float = 1.0 - relation_penalty
    var raw: Dictionary = {"eyes": eye, "nose": nose, "mouth": mouth, "brows": brows, "bone": bone, "harmony": harmony}
    var details: Dictionary = {}
    var total: float = 0.0
    for key in WEIGHTS:
        details[key] = snappedf(clampf(float(raw[key]), 0.0, 1.0) * float(WEIGHTS[key]), 0.01)
        total += float(details[key])
    total = clampf(snappedf(total, 0.01), 0.0, 100.0)
    var band: String = "low"
    if total > 80.0:
        band = "high"
    elif total >= 50.0:
        band = "ordinary"
    return {"model_version": "appearance-score-test-0.1", "calibration_status": "uncalibrated", "total": total, "tier": band, "breakdown": details, "note": "只用于开发流程验证，分数未经人物盲评校准；不可代表真实容貌评价。"}
