#+build !js
package common

import "core:testing"

@(test)
test_the_mixer_plays_sums_loops_and_stops :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Mixer
	defer mixer_free(&m)
	out := make([]i16, 6, context.temp_allocator)
	// Nothing playing is silence.
	mixer_render(&m, out, SOUND_RATE)
	testing.expect(t, out[0] == 0 && out[5] == 0)
	// One voice, played once: its samples, then it stops by itself.
	mixer_apply(&m, {action = .Play, channel = 0, samples = {1, 2, 3, 4}})
	testing.expect_value(t, mixer_active(&m), 1)
	mixer_render(&m, out, SOUND_RATE)
	testing.expect(t, out[0] == 1 && out[3] == 4 && out[4] == 0 && out[5] == 0)
	testing.expect_value(t, mixer_active(&m), 0)
	// Two voices add; a loop wraps; Stop silences just its channel.
	mixer_apply(&m, {action = .Play, channel = 0, samples = {10, 20}, loop = true})
	mixer_apply(&m, {action = .Play, channel = 2, samples = {1, 1, 1}})
	mixer_render(&m, out, SOUND_RATE)
	testing.expect(t, out[0] == 11 && out[1] == 21 && out[2] == 11 && out[3] == 20 && out[4] == 10 && out[5] == 20)
	mixer_apply(&m, {action = .Stop, channel = 0})
	testing.expect_value(t, mixer_active(&m), 0) // channel 2 ended on its own above
	// A new sound on a busy channel replaces it; Stop_All stops everything.
	mixer_apply(&m, {action = .Play, channel = 1, samples = {5, 5, 5, 5, 5, 5, 5, 5}})
	mixer_apply(&m, {action = .Play, channel = 1, samples = {7, 7, 7, 7, 7, 7, 7, 7}})
	mixer_render(&m, out, SOUND_RATE)
	testing.expect(t, out[0] == 7 && out[5] == 7)
	mixer_apply(&m, {action = .Stop_All})
	testing.expect_value(t, mixer_active(&m), 0)
	// Bad requests do nothing.
	mixer_apply(&m, {action = .Play, channel = 9, samples = {1}})
	mixer_apply(&m, {action = .Play, channel = -1, samples = {1}})
	mixer_apply(&m, {action = .Play, channel = 0})
	mixer_apply(&m, {action = .Stop, channel = 77})
	testing.expect_value(t, mixer_active(&m), 0)
}

@(test)
test_the_mixer_clips_and_resamples :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Mixer
	defer mixer_free(&m)
	out := make([]i16, 4, context.temp_allocator)
	mixer_apply(&m, {action = .Play, channel = 0, samples = {30000, -30000, 30000, -30000}})
	mixer_apply(&m, {action = .Play, channel = 1, samples = {30000, -30000, 30000, -30000}})
	mixer_render(&m, out, SOUND_RATE)
	testing.expect(t, out[0] == 32767 && out[1] == -32768 && out[2] == 32767 && out[3] == -32768) // clipped, not wrapped
	// A source at half the output rate plays each sample twice; at double it skips every other one.
	mixer_apply(&m, {action = .Stop_All})
	big := make([]i16, 8, context.temp_allocator)
	mixer_apply(&m, {action = .Play, channel = 0, samples = {1, 2, 3, 4}, rate = 1000})
	mixer_render(&m, big, 2000)
	testing.expect(t, big[0] == 1 && big[1] == 1 && big[2] == 2 && big[3] == 2 && big[6] == 4 && big[7] == 4)
	mixer_apply(&m, {action = .Play, channel = 0, samples = {1, 2, 3, 4}, rate = 2000})
	mixer_render(&m, out, 1000)
	testing.expect(t, out[0] == 1 && out[1] == 3 && out[2] == 0)
	// The mixer copies: changing the request's samples afterwards changes nothing.
	src := []i16{9, 9, 9, 9}
	mixer_apply(&m, {action = .Play, channel = 3, samples = src})
	src[0] = 0
	mixer_render(&m, out, SOUND_RATE)
	testing.expect_value(t, out[0], i16(9))
	mixer_render(&m, out, 0) // a nonsense output rate is silence, not a crash
	testing.expect_value(t, out[0], i16(0))
}

Audio_Probe :: struct {
	queue: [dynamic]Audio_Request,
}

@(test)
test_a_frontend_applies_a_tools_audio_requests :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	probe: Audio_Probe
	probe.queue.allocator = context.temp_allocator
	tool := Tool {
		data = &probe,
		take_audio = proc(data: rawptr) -> (Audio_Request, bool) {
			p := (^Audio_Probe)(data)
			if len(p.queue) == 0 {
				return {}, false
			}
			return pop_front(&p.queue), true
		},
	}
	m: Mixer
	defer mixer_free(&m)
	// A tool without audio is fine, and so is one with nothing queued.
	tool_service_audio(&Tool{}, &m)
	tool_service_audio(&tool, &m)
	testing.expect_value(t, mixer_active(&m), 0)
	// Several requests in one frame are all applied, in order.
	append(&probe.queue, Audio_Request{action = .Play, channel = 0, samples = {1, 1}}, Audio_Request{action = .Play, channel = 1, samples = {2, 2}}, Audio_Request{action = .Stop, channel = 0})
	tool_service_audio(&tool, &m)
	testing.expect_value(t, mixer_active(&m), 1)
	testing.expect_value(t, len(probe.queue), 0)
}
