#ifndef TEST_LOGOT_PROFILER_H
#define TEST_LOGOT_PROFILER_H

#include "modules/logot_profiler/logot_profiler_bridge.h"
#include "tests/test_macros.h"

namespace TestLogotProfiler {

static inline RenderingServerTypes::FrameProfileArea area(const StringName &p_name, double p_cpu, double p_gpu) {
	RenderingServerTypes::FrameProfileArea result;
	result.name = p_name;
	result.cpu_msec = p_cpu;
	result.gpu_msec = p_gpu;
	return result;
}

TEST_CASE("[LogotProfiler] Nested render areas produce exclusive, complete source totals") {
	Vector<RenderingServerTypes::FrameProfileArea> areas;
	areas.push_back(area(">Scene", 0.0, 0.0));
	areas.push_back(area("Draw", 1.0, 2.0));
	areas.push_back(area("<Scene", 4.0, 5.0));
	areas.push_back(area("Frame end", 5.0, 7.0));

	Dictionary frame = LogotProfilerBridge::parse_render_areas(areas, 42);
	CHECK(int64_t(frame["frame_number"]) == 42);
	CHECK(double(frame["render_cpu_total_ms"]) == doctest::Approx(5.0));
	CHECK(double(frame["gpu_total_ms"]) == doctest::Approx(7.0));
	CHECK(bool(frame["gpu_breakdown_available"]));

	double cpu_sum = 0.0;
	double gpu_sum = 0.0;
	Array sources = frame["render_sources"];
	for (int i = 0; i < sources.size(); i++) {
		Dictionary source = sources[i];
		cpu_sum += double(source["cpu_ms"]);
		gpu_sum += double(source["gpu_ms"]);
	}
	CHECK(cpu_sum == doctest::Approx(5.0));
	CHECK(gpu_sum == doctest::Approx(7.0));
}

TEST_CASE("[LogotProfiler] Whole-frame Metal fallback does not fabricate source timings") {
	Vector<RenderingServerTypes::FrameProfileArea> areas;
	areas.push_back(area(">Scene", 0.0, 0.0));
	areas.push_back(area("Draw", 1.0, 0.0));
	areas.push_back(area("<Scene", 2.0, 0.0));
	areas.push_back(area("Frame end", 3.0, 4.5));

	Dictionary frame = LogotProfilerBridge::parse_render_areas(areas, 43);
	CHECK(bool(frame["gpu_available"]));
	CHECK_FALSE(bool(frame["gpu_breakdown_available"]));
	CHECK(double(frame["gpu_total_ms"]) == doctest::Approx(4.5));
	Array sources = frame["render_sources"];
	for (int i = 0; i < sources.size(); i++) {
		Dictionary source = sources[i];
		CHECK(double(source["gpu_ms"]) == doctest::Approx(0.0));
	}
}

TEST_CASE("[LogotProfiler] Source retention caps named entries and preserves the remainder") {
	Vector<RenderingServerTypes::FrameProfileArea> areas;
	for (int i = 0; i <= 70; i++) {
		areas.push_back(area(StringName("Source " + itos(i)), double(i), double(i)));
	}

	Dictionary frame = LogotProfilerBridge::parse_render_areas(areas, 7);
	Array sources = frame["render_sources"];
	CHECK(sources.size() == LogotProfilerBridge::MAX_RETAINED_SOURCES + 1);
	bool found_other = false;
	double total = 0.0;
	for (int i = 0; i < sources.size(); i++) {
		Dictionary source = sources[i];
		found_other = found_other || String(source["path"]) == "__other__";
		total += double(source["cpu_ms"]);
	}
	CHECK(found_other);
	CHECK(total == doctest::Approx(70.0));
}

} // namespace TestLogotProfiler

#endif
