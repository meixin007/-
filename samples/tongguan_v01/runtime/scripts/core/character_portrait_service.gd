extends RefCounted
## Read-only projection: recipes consume persisted DNA and the single game clock.
const Appearance = preload("res://scripts/core/character_appearance_contract.gd")
const Recipe = preload("res://tang_dna_v3_2/scripts/appearance_recipe.gd")
const Io = preload("res://tang_dna_v3_2/scripts/data_io.gd")

func build_recipe(context, character_id: String) -> Dictionary:
	if context==null or context.state==null: return Appearance.fail("missing_portrait_context")
	var decoded: Dictionary = Appearance.decode_character(context.state,character_id)
	if not decoded.ok: return decoded
	var profile: Dictionary = Io.read_cached_dictionary("res://tang_dna_v3_2/data/tang_830.json")
	var catalog: Dictionary = Io.read_cached_dictionary("res://tang_dna_v3_2/data/asset_catalog_octopath.json")
	# Candidate clothes are cosmetic common robes; this projection grants no
	# rank, equipment, clothing ownership or historical-year entitlement.
	var definition: Dictionary = Appearance.schema()
	var recipe: Dictionary = Recipe.build(decoded.character,{"year":int(profile.reference_year),"occasion":"private"},definition,profile,catalog)
	if recipe.get("ok",false):
		# Candidate capability is separate from the incomplete formal asset rig.
		recipe["candidate_render_mode"]="tang_child_growth" if float(decoded.character.appearance_state.age_years)<float(definition.adult_rig_min_age) else "tang_styled_parts"
	return recipe
