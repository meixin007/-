extends RefCounted
var submissions: Array=[]
var errors: Array=[]
var _seen: Dictionary={}
var _entities: Dictionary={}
var _pairs: Dictionary={}
func begin_frame() -> void:submissions=[];errors=[];_seen={};_entities={};_pairs={}
func register_pair(id: String,old_rep: String,new_rep: String,transition: String) -> bool:
	if id.is_empty() or old_rep.is_empty() or new_rep.is_empty() or old_rep==new_rep or transition.is_empty() or _pairs.has(id):return false
	_pairs[id]={"representations":[old_rep,new_rep],"transition":transition};return true
func submit(id: String,representation: String="detail",transition: String="") -> Dictionary:
	var key:=JSON.stringify([id,representation])
	var code:=""
	if id.is_empty() or representation.is_empty():code="invalid_submission_identity"
	elif _seen.has(key):code="duplicate_representation"
	elif _entities.has(id):
		if not _pairs.has(id) or transition!=_pairs[id].transition or representation not in _pairs[id].representations or _entities[id].size()>=2:code="unregistered_representation_pair"
		else:
			for previous in _entities[id]:
				if previous.transition!=transition or previous.representation not in _pairs[id].representations:code="unregistered_representation_pair"
	if not code.is_empty():errors.append({"id":id,"representation":representation,"code":code});return {"ok":false,"code":code}
	_seen[key]=true
	if not _entities.has(id):_entities[id]=[]
	_entities[id].append({"representation":representation,"transition":transition})
	submissions.append({"id":id,"representation":representation,"transition":transition})
	return {"ok":true}
