const std = @import("std");

const MAX_STACK_SIZE = 1024 * 1024;

// /// Stack-allocated buffer, we avoid heap allocations for the
// /// sheer fact and a real argument of:
// /// ```
// /// LamaRpreter: runtime.c:807: void *Bstring(aint *): Assertion `__builtin_frame_address(0) <= (void *)__gc_stack_top' failed.
// /// ``
// const Stack = struct {
//     data: [MAX_STACK_SIZE]i64,

// }
