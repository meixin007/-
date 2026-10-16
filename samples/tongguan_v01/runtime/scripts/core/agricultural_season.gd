extends RefCounted

# A production season is a contiguous, ordered window of game-calendar months.
# Its identity is the year of the first month, even when sowing or harvesting
# occurs after New Year. No new clock, mutable registry, or Gregorian conversion.
const Calendar = preload("res://scripts/core/strategic_time_service.gd")
const Numbers = preload("res://scripts/core/public_works_service.gd")

static func fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func contains_month(months: Array, month: int) -> bool:
	return months.any(func(value): return int(value) == month)

static func validate(rule: Dictionary) -> Dictionary:
	for key in ["plant_months", "growth_months", "harvest_months"]:
		if not rule.get(key) is Array or rule[key].is_empty(): return fail("作物缺少农时")
		var seen := {}
		for value in rule[key]:
			if not Numbers.number(value, 1, Calendar.MONTHS_PER_YEAR) or seen.has(int(value)): return fail("作物农时无效或重复")
			seen[int(value)] = true
	var months: Array = rule.growth_months
	for index in range(1, months.size()):
		if int(months[index]) != int(months[index - 1]) % Calendar.MONTHS_PER_YEAR + 1:
			return fail("生长季月份须按实际先后连续排列，可跨年但不能跳月或倒序")
	for key in ["plant_months", "harvest_months"]:
		for value in rule[key]:
			if not contains_month(months, int(value)): return fail("播种或收割月份不在生长季")
	return {"ok": true}

static func season_year(rule: Dictionary, date: Dictionary) -> int:
	if not contains_month(rule.growth_months, int(date.month)): return -1
	return int(date.year) - (1 if int(date.month) < int(rule.growth_months[0]) else 0)

static func within(rule: Dictionary, year: int, date: Dictionary) -> bool:
	return season_year(rule, date) == year

static func at_serial(serial: int) -> Dictionary:
	var months := Calendar.MONTHS_PER_YEAR
	var days := Calendar.DAYS_PER_MONTH
	return {"year": serial / (months * days), "month": (serial / days) % months + 1, "day": serial % days + 1}
