class_name PortraitDataIo
extends RefCounted
static var _cache: Dictionary = {}

static func read_cached_dictionary(path: String) -> Dictionary:
    if not _cache.has(path):
        var value: Dictionary = read_dictionary(path)
        if value.is_empty():
            return {}
        _cache[path] = value
    return _cache[path].duplicate(true)

static func clear_cache() -> void:
    _cache.clear()


static func read_dictionary(path: String) -> Dictionary:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("无法读取 JSON: " + path)
        return {}
    var parser: JSON = JSON.new()
    var result: Error = parser.parse(file.get_as_text())
    if result != OK or typeof(parser.data) != TYPE_DICTIONARY:
        push_error("JSON 根节点须为对象: " + path + " " + parser.get_error_message())
        return {}
    return parser.data


static func save_dictionary(path: String, value: Dictionary) -> Error:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    # full_precision=true 保留 float 精确往返所需位数。
    file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
    return OK

