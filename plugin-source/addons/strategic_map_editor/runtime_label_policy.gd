extends RefCounted
## Display categories only; these names never define political ownership.
const COUNTRIES := ["唐","日本","吐蕃","后突厥","突骑施","渤海","新罗","南诏","骠国","真腊","环王","天竺诸国"]
static func tier_for_zoom(camera_zoom: float, fit_zoom: float) -> String:
	var ratio := camera_zoom / maxf(fit_zoom,0.001)
	if ratio < 1.8: return "country"
	if ratio < 4.0: return "region"
	if ratio < 9.0: return "prefecture"
	return "close"
static func feature_tier(feature: Dictionary) -> String:
	if feature.get("kind","") != "label": return ""
	var explicit: String = feature.get("visual",{}).get("runtime_label_tier","")
	if explicit in ["country","region","prefecture"]: return explicit
	var group: String = feature.get("group_id","")
	if group == "state_names": return "prefecture"
	if group == "atlas_labels":
		return "country" if feature.get("name","") in COUNTRIES else "region"
	return ""
static func pixel_size(tier: String) -> float:
	return 26.0 if tier == "country" else (20.0 if tier == "region" else 15.0)
static func title(tier: String) -> String:
	return {"country":"国名","region":"道名 / 分区","prefecture":"州名","close":"城池近景"}.get(tier,"")
