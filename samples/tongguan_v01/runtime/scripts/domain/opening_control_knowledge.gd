extends RefCounted
## Scenario opening beliefs, not live territorial authority or historical proof.
## Dates before day zero retain the former opening dispatch age explicitly.
const SOURCE := "scenario:opening_control_beliefs_756_v1"
const RECORDS := {
	"lingwu_court_node":["tang_court",0,false],
	"shuofang_front_node":["tang_court",0,false],
	"grain_road_node":["tang_court",-1,false],
	"guanzhong_approach_node":["tang_court",-1,false],
	"changan_pressure_node":["tang_rebel",-2,false],
	"tongguan_pass_node":["tang_rebel",-2,false],
	"hedong_relay_node":["tang_court",-1,false],
	"taiyuan_hub_node":["tang_court",-1,false],
	"uighur_route_node":["foreign_huihe",-4,false],
	"hebei_rebel_signal_node":["tang_rebel",-5,true],
	"fanyang_rebel_hub_node":["tang_rebel",-5,true],
	"luoyang_rumor_node":["tang_rebel",-2,false],
	"suiyang_hub_node":["tang_court",-7,false],
	"yangzhou_tribute_hub_node":["tang_court",-7,false],
	"refugee_market_node":["disputed",-3,false],
	"palace_inner_channel_node":["disputed",-3,false],
	"desert_envoy_road_node":["tang_court",-1,false],
	"jianmen_pass_node":["tang_court",-10,false],
	"chengdou_rear_hub_node":["tang_court",-10,false]
}

static func project(day: int, isolated: bool) -> Dictionary:
	var result := {}
	for node in RECORDS:
		if isolated and node not in ["lingwu_court_node","shuofang_front_node"]:
			result[node]={"status":"fog_of_war","latency_days":99,"intelligence_note":"暂无已收控制资料","visible_faction":"unknown"}
			continue
		var row: Array=RECORDS[node]
		var age: int=maxi(0,day-int(row[1]))
		result[node]={"status":"rumor" if row[2] else ("confirmed" if age==0 else "delayed"),"latency_days":age,"observed_day":int(row[1]),"visible_faction":row[0],"source_refs":[SOURCE+":"+node],"intelligence_note":"开局控制资料 · %s · 已过 %d 日；尚未取得此后回报" % ["开局前%d日" % absi(int(row[1])) if row[1]<0 else "第0日",age]}
	return result
