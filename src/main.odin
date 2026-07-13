package main

@(require) import "core:fmt"
import "core:log"
@(require) import "core:mem"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	logger := log.create_console_logger(.Info, {.Level})
	context.logger = logger
	defer log.destroy_console_logger(logger)

	when ODIN_OS != .Windows {
		log.error("This build targets Windows 10/11 only.")
		return
	}

	run_imgoptz()
}
