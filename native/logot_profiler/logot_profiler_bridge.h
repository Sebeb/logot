#ifndef LOGOT_PROFILER_BRIDGE_H
#define LOGOT_PROFILER_BRIDGE_H

#include "core/object/object.h"
#include "core/object/script_language.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "servers/rendering/rendering_server_types.h"

class LogotProfilerBridge : public Object {
	GDCLASS(LogotProfilerBridge, Object);

public:
	static constexpr int API_VERSION = 1;
	static constexpr int MAX_RETAINED_SOURCES = 64;
	static constexpr int MAX_PENDING_FRAMES = 16;
	static Dictionary parse_render_areas(const Vector<RenderingServerTypes::FrameProfileArea> &p_areas, uint64_t p_frame_number);

private:
	bool render_requested = false;
	bool scripts_requested = false;
	bool owns_render_profiling = false;
	bool owns_script_profiling = false;
	bool previous_builtin_visual_active = false;
	bool previous_builtin_servers_active = false;
	bool process_frame_connected = false;
	uint64_t poll_count = 0;
	uint64_t render_start_count = 0;
	uint64_t render_stop_count = 0;
	int64_t last_render_request_frame = -100;
	int64_t last_script_request_frame = -100;
	uint64_t last_render_profile_frame = 0;
	int last_render_profile_size = 0;
	bool render_profile_seen = false;
	bool gpu_timestamps_seen = false;
	bool script_profile_seen = false;
	bool script_signatures_seen = false;
	int64_t last_captured_render_frame = -1;
	int64_t last_captured_script_frame = -1;
	Array pending_frames;
	Vector<ScriptLanguage::ProfilingInfo> script_info;

	void _connect_process_frame();
	void _disconnect_process_frame();
	void _on_process_frame();
	void _start_render_profiling();
	void _stop_render_profiling();
	void _start_script_profiling();
	void _stop_script_profiling();
	Dictionary _capture_render_frame();
	Dictionary _capture_script_frame();
	void _append_pending_frame(const Dictionary &p_frame);

protected:
	static void _bind_methods();

public:
	int get_api_version() const;
	void set_capture_enabled(bool p_render_sources, bool p_script_sources);
	void poll_frame();
	Array drain_frames();
	Dictionary get_status() const;

	LogotProfilerBridge();
	~LogotProfilerBridge();
};

#endif
