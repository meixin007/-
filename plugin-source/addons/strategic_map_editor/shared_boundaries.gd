@tool
extends RefCounted
## Opt-in shared vertices for authoring maps. All affected rings commit atomically.
static func _vec(p: Array) -> Vector2:
	return Vector2(p[0],p[1])
static func _rings(f: Dictionary) -> Array:
	return [f.points]+f.holes
static func apply(features: Array, before: Dictionary, after: Dictionary, locked: Array) -> bool:
	var set_id: String=before.get("visual",{}).get("shared_boundary_set","")
	if set_id.is_empty():return true
	if before.get("protected",false):return false
	var old_rings:=_rings(before);var new_rings:=_rings(after)
	if old_rings.size()!=new_rings.size():return false
	var moves: Dictionary={};var removals: Dictionary={};var inserts: Array=[]
	for r in range(old_rings.size()):
		var old: Array=old_rings[r];var fresh: Array=new_rings[r]
		if old==fresh:continue
		if old.size()==fresh.size():
			for i in range(old.size()):
				if old[i]!=fresh[i]:moves[_vec(old[i])]=fresh[i].duplicate()
		elif fresh.size()==old.size()+1:
			var index:=0
			while index<old.size() and old[index]==fresh[index]:index+=1
			var restored:=fresh.duplicate(true);var added: Array=restored.pop_at(index)
			if restored!=old or old.size()<2:return false
			var closed: bool=before.kind=="prefecture" or r>0
			if not closed and (index==0 or index==fresh.size()-1):return false
			inserts.append([_vec(old[posmod(index-1,old.size())]),_vec(old[index%old.size()]),added])
		elif fresh.size()==old.size()-1:
			var index:=0
			while index<fresh.size() and old[index]==fresh[index]:index+=1
			var restored:=old.duplicate(true);var removed: Array=restored.pop_at(index)
			if restored!=fresh:return false
			removals[_vec(removed)]=true
			if before.kind!="prefecture" and old.size()>2 and old[0]==old[-1] and removed==old[0]:
				var closed_points: Array=[]
				for p in fresh:
					if p!=removed:closed_points.append(p.duplicate())
				if closed_points.size()<2:return false
				closed_points.append(closed_points[0].duplicate())
				fresh.clear();fresh.append_array(closed_points)
		else:return false
	# Closed line features duplicate their first vertex at the end. Preserve
	# that closure when the user drags only one copy of the endpoint.
	for r in range(old_rings.size()):
		if old_rings[r].size()!=new_rings[r].size():continue
		for i in range(old_rings[r].size()):
			var point:=_vec(old_rings[r][i])
			if old_rings[r][i]==new_rings[r][i] and moves.has(point):
				new_rings[r][i]=moves[point].duplicate()
	for f in features:
		if f.id==before.id or f.get("visual",{}).get("shared_boundary_set","")!=set_id:continue
		var touched:=false;var rings:=_rings(f)
		for ri in range(rings.size()):
			var ring: Array=rings[ri]
			var updated: Array=[]
			var closed: bool=f.kind=="prefecture" or ri>0
			for i in range(ring.size()):
				var point:=_vec(ring[i])
				if removals.has(point):touched=true;continue
				if moves.has(point):updated.append(moves[point].duplicate());touched=true
				else:updated.append(ring[i].duplicate())
				if i==ring.size()-1 and not closed:continue
				var next_point:=_vec(ring[(i+1)%ring.size()])
				for insert in inserts:
					if (point==insert[0] and next_point==insert[1]) or (point==insert[1] and next_point==insert[0]):
						updated.append(insert[2].duplicate());touched=true
			if not closed and ring.size()>2 and ring[0]==ring[-1] and updated.size()>1 and updated[0]!=updated[-1]:
				updated.append(updated[0].duplicate())
			if ri==0:f.points=updated
			else:f.holes[ri-1]=updated
		if touched and (f.layer in locked or f.get("protected",false)):return false
	return true
