#include "logot_profiler_bridge.h"

#include "core/config/engine.h"
#include "core/debugger/engine_debugger.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/string/print_string.h"
#include "scene/main/scene_tree.h"
#include "servers/rendering/rendering_server.h"

namespace {
struct SourceTimes {
	double cpu_msec = 0.0;
	double gpu_msec = 0.0;
	String display_name;
};

struct RankedSource {
	String path;
	SourceTimes times;
};

struct RankedSourceComparator {
	bool operator()(const RankedSource &p_a, const RankedSource &p_b) const {
		const double a_time = MAX(p_a.times.cpu_msec, p_a.times.gpu_msec);
		const double b_time = MAX(p_b.times.cpu_msec, p_b.times.gpu_msec);
		if (Math::is_equal_approx(a_time, b_time)) {
			return p_a.path < p_b.path;
		}
		return a_time > b_time;
	}
};

String join_stack_path(const Vector<String> &p_stack) {
	String path;
	for (int i = 0; i < p_stack.size(); i++) {
		if (!path.is_empty()) {
			path += "/";
		}
		path += p_stack[i];
	}
	return path;
}

String source_display_name(const String &p_path) {
	const int signature_separator = p_path.rfind("::");
	if (signature_separator >= 0) {
		return p_path.substr(signature_separator + 2);
	}
	const int separator = p_path.rfind("/");
	return separator >= 0 ? p_path.substr(separator + 1) : p_path;
}
} // namespace

void LogotProfilerBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_api_version"), &LogotProfilerBridge::get_api_version);
	ClassDB::bind_method(D_METHOD("set_capture_enabled", "render_sources", "script_sources"), &LogotProfilerBridge::set_capture_enabled);
	ClassDB::bind_method(D_METHOD("poll_frame"), &LogotProfilerBridge::poll_frame);
	ClassDB::bind_method(D_METHOD("drain_frames"), &LogotProfilerBridge::drain_frames);
	ClassDB::bind_method(D_METHOD("get_status"), &LogotProfilerBridge::get_status);
}

int LogotProfilerBridge::get_api_version() const {
	return API_VERSION;
}

void LogotProfilerBridge::_connect_process_frame() {
	if (process_frame_connected) {
		return;
	}
	SceneTree *tree = Object::cast_to<SceneTree>(OS::get_singleton()->get_main_loop());
	if (tree == nullptr) {
		return;
	}
	const Callable callback(this, SNAME("poll_frame"));
	if (!tree->is_connected(SNAME("process_frame"), callback)) {
		tree->connect(SNAME("process_frame"), callback);
	}
	process_frame_connected = true;
}

void LogotProfilerBridge::_disconnect_process_frame() {
	if (!process_frame_connected) {
		return;
	}
	SceneTree *tree = Object::cast_to<SceneTree>(OS::get_singleton()->get_main_loop());
	const Callable callback(this, SNAME("poll_frame"));
	if (tree != nullptr && tree->is_connected(SNAME("process_frame"), callback)) {
		tree->disconnect(SNAME("process_frame"), callback);
	}
	process_frame_connected = false;
}

void LogotProfilerBridge::_start_render_profiling() {
	render_start_count++;
	const bool builtin_active = EngineDebugger::is_profiling(SNAME("visual"));
	previous_builtin_visual_active = builtin_active;
	if (!builtin_active) {
		RenderingServer::get_singleton()->set_frame_profiling_enabled(true);
		owns_render_profiling = true;
	}
}

void LogotProfilerBridge::_stop_render_profiling() {
	render_stop_count++;
	const bool builtin_active = EngineDebugger::is_profiling(SNAME("visual"));
	if (owns_render_profiling && !builtin_active) {
		RenderingServer::get_singleton()->set_frame_profiling_enabled(false);
	}
	owns_render_profiling = false;
	previous_builtin_visual_active = builtin_active;
}

void LogotProfilerBridge::_start_script_profiling() {
	const bool builtin_active = EngineDebugger::is_profiling(SNAME("servers"));
	previous_builtin_servers_active = builtin_active;
	if (!builtin_active) {
		for (int i = 0; i < ScriptServer::get_language_count(); i++) {
			ScriptServer::get_language(i)->profiling_start();
		}
		owns_script_profiling = true;
	}
}

void LogotProfilerBridge::_stop_script_profiling() {
	const bool builtin_active = EngineDebugger::is_profiling(SNAME("servers"));
	if (owns_script_profiling && !builtin_active) {
		for (int i = 0; i < ScriptServer::get_language_count(); i++) {
			ScriptServer::get_language(i)->profiling_stop();
		}
	}
	owns_script_profiling = false;
	previous_builtin_servers_active = builtin_active;
}

void LogotProfilerBridge::set_capture_enabled(bool p_render_sources, bool p_script_sources) {
	const int64_t current_frame = int64_t(Engine::get_singleton()->get_process_frames());
	if (p_render_sources) {
		last_render_request_frame = current_frame;
		if (!render_requested) {
			_start_render_profiling();
			render_requested = true;
		}
	} else if (render_requested && current_frame > last_render_request_frame + 2) {
		_stop_render_profiling();
		render_requested = false;
	}
	if (p_script_sources) {
		last_script_request_frame = current_frame;
		if (!scripts_requested) {
			_start_script_profiling();
			scripts_requested = true;
		}
	} else if (scripts_requested && current_frame > last_script_request_frame + 2) {
		_stop_script_profiling();
		scripts_requested = false;
	}

	if (render_requested || scripts_requested) {
		_connect_process_frame();
	} else {
		_disconnect_process_frame();
	}
}

void LogotProfilerBridge::_append_pending_frame(const Dictionary &p_frame) {
	if (p_frame.is_empty()) {
		return;
	}
	pending_frames.push_back(p_frame);
	while (pending_frames.size() > MAX_PENDING_FRAMES) {
		pending_frames.pop_front();
	}
}

Dictionary LogotProfilerBridge::_capture_render_frame() {
	Vector<RenderingServerTypes::FrameProfileArea> areas = RenderingServer::get_singleton()->get_frame_profile();
	last_render_profile_size = areas.size();
	last_render_profile_frame = RenderingServer::get_singleton()->get_frame_profile_frame();
	render_profile_seen = render_profile_seen || !areas.is_empty();
	for (const RenderingServerTypes::FrameProfileArea &area : areas) {
		gpu_timestamps_seen = gpu_timestamps_seen || area.gpu_msec > 0.0;
	}
	return parse_render_areas(areas, last_render_profile_frame);
}

Dictionary LogotProfilerBridge::parse_render_areas(const Vector<RenderingServerTypes::FrameProfileArea> &areas, uint64_t p_frame_number) {
	Dictionary result;
	if (areas.size() < 2) {
		return result;
	}

	HashMap<String, SourceTimes> source_map;
	if (areas[0].cpu_msec > 0.0 || areas[0].gpu_msec > 0.0) {
		SourceTimes &initial = source_map["Render frame overhead"];
		initial.cpu_msec = MAX(0.0, areas[0].cpu_msec);
		initial.gpu_msec = MAX(0.0, areas[0].gpu_msec);
		initial.display_name = "Render frame overhead";
	}
	Vector<String> stack;
	for (int i = 0; i < areas.size() - 1; i++) {
		const String raw_name = String(areas[i].name).strip_edges();
		const double cpu_delta = MAX(0.0, areas[i + 1].cpu_msec - areas[i].cpu_msec);
		const double gpu_delta = MAX(0.0, areas[i + 1].gpu_msec - areas[i].gpu_msec);
		String path;

		if (raw_name.begins_with(">")) {
			const String category = raw_name.substr(1).strip_edges();
			stack.push_back(category);
			path = join_stack_path(stack) + " (self)";
		} else if (raw_name.begins_with("<")) {
			if (!stack.is_empty()) {
				stack.remove_at(stack.size() - 1);
			}
			const String parent_path = join_stack_path(stack);
			path = parent_path.is_empty() ? "Render frame overhead" : parent_path + " (self)";
		} else {
			const String parent_path = join_stack_path(stack);
			path = parent_path.is_empty() ? raw_name : parent_path + "/" + raw_name;
		}

		if (path.is_empty()) {
			path = "Render frame overhead";
		}
		SourceTimes &times = source_map[path];
		times.cpu_msec += cpu_delta;
		times.gpu_msec += gpu_delta;
		times.display_name = source_display_name(path);
	}

	Vector<RankedSource> ranked;
	ranked.reserve(source_map.size());
	for (const KeyValue<String, SourceTimes> &entry : source_map) {
		RankedSource item;
		item.path = entry.key;
		item.times = entry.value;
		ranked.push_back(item);
	}
	ranked.sort_custom<RankedSourceComparator>();

	Array serialized_sources;
	double other_cpu = 0.0;
	double other_gpu = 0.0;
	for (int i = 0; i < ranked.size(); i++) {
		if (i >= MAX_RETAINED_SOURCES) {
			other_cpu += ranked[i].times.cpu_msec;
			other_gpu += ranked[i].times.gpu_msec;
			continue;
		}
		Dictionary source;
		source["path"] = ranked[i].path;
		source["name"] = ranked[i].times.display_name;
		source["cpu_ms"] = ranked[i].times.cpu_msec;
		source["gpu_ms"] = ranked[i].times.gpu_msec;
		serialized_sources.push_back(source);
	}
	if (other_cpu > 0.0 || other_gpu > 0.0) {
		Dictionary other;
		other["path"] = "__other__";
		other["name"] = "Other";
		other["cpu_ms"] = other_cpu;
		other["gpu_ms"] = other_gpu;
		serialized_sources.push_back(other);
	}

	result["kind"] = "render";
	result["frame_number"] = int64_t(p_frame_number);
	result["render_cpu_total_ms"] = MAX(0.0, areas[areas.size() - 1].cpu_msec);
	result["gpu_total_ms"] = MAX(0.0, areas[areas.size() - 1].gpu_msec);
	result["gpu_available"] = areas[areas.size() - 1].gpu_msec > 0.0;
	result["render_sources"] = serialized_sources;
	return result;
}

Dictionary LogotProfilerBridge::_capture_script_frame() {
	Dictionary result;
	if (script_info.is_empty()) {
		return result;
	}

	HashMap<String, SourceTimes> source_map;
	for (int language_index = 0; language_index < ScriptServer::get_language_count(); language_index++) {
		const int count = ScriptServer::get_language(language_index)->profiling_get_frame_data(script_info.ptrw(), script_info.size());
		script_profile_seen = script_profile_seen || count > 0;
		for (int i = 0; i < count; i++) {
			String path = String(script_info[i].signature);
			if (path.is_empty()) {
				path = "__unnamed_script__";
			} else {
				script_signatures_seen = true;
			}
			SourceTimes &times = source_map[path];
			times.display_name = path == "__unnamed_script__" ? "Engine / Script / Unnamed" : source_display_name(path);
			// GDScript profiler times are microseconds; snapshots expose milliseconds.
			times.cpu_msec += double(script_info[i].self_time) / 1000.0;
			times.gpu_msec += double(script_info[i].call_count);
		}
	}
	Vector<RankedSource> ranked;
	ranked.reserve(source_map.size());
	for (const KeyValue<String, SourceTimes> &entry : source_map) {
		RankedSource item;
		item.path = entry.key;
		item.times = entry.value;
		ranked.push_back(item);
	}
	ranked.sort_custom<RankedSourceComparator>();

	Array serialized_sources;
	double other_msec = 0.0;
	for (int i = 0; i < ranked.size(); i++) {
		if (i >= MAX_RETAINED_SOURCES) {
			other_msec += ranked[i].times.cpu_msec;
			continue;
		}
		Dictionary source;
		source["path"] = ranked[i].path;
		source["name"] = ranked[i].times.display_name;
		source["self_ms"] = ranked[i].times.cpu_msec;
		source["call_count"] = int64_t(ranked[i].times.gpu_msec);
		serialized_sources.push_back(source);
	}
	if (other_msec > 0.0) {
		Dictionary other;
		other["path"] = "__other__";
		other["name"] = "Other";
		other["self_ms"] = other_msec;
		other["call_count"] = 0;
		serialized_sources.push_back(other);
	}

	result["kind"] = "script";
	result["frame_number"] = MAX(int64_t(0), int64_t(Engine::get_singleton()->get_process_frames()) - 1);
	result["script_sources"] = serialized_sources;
	result["script_signatures_available"] = script_signatures_seen;
	return result;
}

void LogotProfilerBridge::_on_process_frame() {
	const bool builtin_visual_active = EngineDebugger::is_profiling(SNAME("visual"));
	const bool builtin_servers_active = EngineDebugger::is_profiling(SNAME("servers"));
	if (render_requested && previous_builtin_visual_active && !builtin_visual_active) {
		RenderingServer::get_singleton()->set_frame_profiling_enabled(true);
		owns_render_profiling = true;
	}
	// The remote debugger can apply a late profiler-disable after module
	// initialization without leaving an observable `visual` ownership state.
	// Reassert our own lease each frame; this is idempotent and never runs while
	// the built-in visual profiler owns collection.
	if (render_requested && owns_render_profiling && !builtin_visual_active) {
		RenderingServer::get_singleton()->set_frame_profiling_enabled(true);
	}
	if (scripts_requested && previous_builtin_servers_active && !builtin_servers_active) {
		for (int i = 0; i < ScriptServer::get_language_count(); i++) {
			ScriptServer::get_language(i)->profiling_start();
		}
		owns_script_profiling = true;
	}
	previous_builtin_visual_active = builtin_visual_active;
	previous_builtin_servers_active = builtin_servers_active;

	if (render_requested) {
		Dictionary render_frame = _capture_render_frame();
		const int64_t frame_number = int64_t(render_frame.get("frame_number", -1));
		if (!render_frame.is_empty() && frame_number != last_captured_render_frame) {
			last_captured_render_frame = frame_number;
			_append_pending_frame(render_frame);
		}
	}
	if (scripts_requested) {
		const int64_t script_frame_number = MAX(int64_t(0), int64_t(Engine::get_singleton()->get_process_frames()) - 1);
		if (script_frame_number != last_captured_script_frame) {
			last_captured_script_frame = script_frame_number;
			_append_pending_frame(_capture_script_frame());
		}
	}
}

void LogotProfilerBridge::poll_frame() {
	poll_count++;
	_on_process_frame();
}

Array LogotProfilerBridge::drain_frames() {
	Array result = pending_frames.duplicate(true);
	pending_frames.clear();
	return result;
}

Dictionary LogotProfilerBridge::get_status() const {
	Dictionary status;
	status["available"] = true;
	status["api_version"] = API_VERSION;
	status["render_requested"] = render_requested;
	status["scripts_requested"] = scripts_requested;
	status["owns_render_profiling"] = owns_render_profiling;
	status["owns_script_profiling"] = owns_script_profiling;
	status["builtin_visual_active"] = EngineDebugger::is_profiling(SNAME("visual"));
	status["builtin_servers_active"] = EngineDebugger::is_profiling(SNAME("servers"));
	status["poll_count"] = int64_t(poll_count);
	status["render_start_count"] = int64_t(render_start_count);
	status["render_stop_count"] = int64_t(render_stop_count);
	status["last_render_profile_frame"] = int64_t(last_render_profile_frame);
	status["last_render_profile_size"] = last_render_profile_size;
	status["render_profile_seen"] = render_profile_seen;
	status["gpu_timestamps_available"] = gpu_timestamps_seen;
	status["script_profile_seen"] = script_profile_seen;
	status["script_signatures_available"] = script_signatures_seen;
	status["pending_frame_count"] = pending_frames.size();
	return status;
}

LogotProfilerBridge::LogotProfilerBridge() {
	script_info.resize(1024);
}

LogotProfilerBridge::~LogotProfilerBridge() {
	if (render_requested) {
		_stop_render_profiling();
		render_requested = false;
	}
	if (scripts_requested) {
		_stop_script_profiling();
		scripts_requested = false;
	}
	_disconnect_process_frame();
}
