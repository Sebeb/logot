#include "register_types.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "logot_profiler_bridge.h"

#ifdef TESTS_ENABLED
#include "tests/test_logot_profiler.h"
#endif

static LogotProfilerBridge *logot_profiler_bridge = nullptr;

void initialize_logot_profiler_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_CLASS(LogotProfilerBridge);
	logot_profiler_bridge = memnew(LogotProfilerBridge);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LogotProfilerBridge", logot_profiler_bridge));
}

void uninitialize_logot_profiler_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	if (logot_profiler_bridge != nullptr) {
		Engine::get_singleton()->remove_singleton("LogotProfilerBridge");
		memdelete(logot_profiler_bridge);
		logot_profiler_bridge = nullptr;
	}
}
