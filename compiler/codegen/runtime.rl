// Internal fast paths use the single-threaded cooperative runtime's ARC ABI.
// Final teardown stays in C: it owns deinit/resurrection/GC unlink/free behavior.
pub def llvm_arc_helpers() -> String {
    """define internal void @"__rolang_obj_retain"(ptr %object) alwaysinline {
entry:
  %is_null = icmp eq ptr %object, null
  br i1 %is_null, label %done, label %increment
increment:
  %rc = load i64, ptr %object, align 8
  %next = add i64 %rc, 1
  store i64 %next, ptr %object, align 8
  br label %done
done:
  ret void
}

define internal void @"__rolang_obj_release"(ptr %object) alwaysinline {
entry:
  %is_null = icmp eq ptr %object, null
  br i1 %is_null, label %done, label %decrement
decrement:
  %rc = load i64, ptr %object, align 8
  %next = sub i64 %rc, 1
  store i64 %next, ptr %object, align 8
  %last = icmp eq i64 %rc, 1
  br i1 %last, label %slow, label %done
slow:
  call void @"rt_obj_release_slow"(ptr %object)
  br label %done
done:
  ret void
}
"""
}


// Bins and header/global offsets match runtime/abi.h and runtime/memory.c.
// Only fully written payloads may use this no-init allocator. GC skips the
// newly linked head while the caller has not yet installed its payload.
pub def llvm_alloc_helper() -> String {
    """@pool_free_lists = external global [6 x ptr]
@gc_object_list = external global ptr
@gc_alloc_counter = external global i64
@gc_trigger_at = external global i64
@gc_running = external global i32
define internal ptr @"__rolang_obj_alloc_fast"(i64 %size, i64 %align, i64 %type_id, i64 %bin) alwaysinline {
entry:
  %slot = getelementptr [6 x ptr], ptr @pool_free_lists, i64 0, i64 %bin
  %node = load ptr, ptr %slot, align 8
  %empty = icmp eq ptr %node, null
  br i1 %empty, label %slow, label %fast
fast:
  %next_free = load ptr, ptr %node, align 8
  store ptr %next_free, ptr %slot, align 8
  store i64 1, ptr %node, align 8
  %tid = getelementptr i8, ptr %node, i64 8
  store i64 %type_id, ptr %tid, align 8
  %prev = getelementptr i8, ptr %node, i64 16
  store ptr null, ptr %prev, align 8
  %head = load ptr, ptr @gc_object_list, align 8
  %next = getelementptr i8, ptr %node, i64 24
  store ptr %head, ptr %next, align 8
  %head_null = icmp eq ptr %head, null
  br i1 %head_null, label %linked, label %set_prev
set_prev:
  %head_prev = getelementptr i8, ptr %head, i64 16
  store ptr %node, ptr %head_prev, align 8
  br label %linked
linked:
  store ptr %node, ptr @gc_object_list, align 8
  %count = load i64, ptr @gc_alloc_counter, align 8
  %increment = add i64 %count, 1
  store i64 %increment, ptr @gc_alloc_counter, align 8
  %trigger = load i64, ptr @gc_trigger_at, align 8
  %due = icmp sge i64 %increment, %trigger
  br i1 %due, label %poll, label %done
poll:
  %running = load i32, ptr @gc_running, align 4
  %busy = icmp ne i32 %running, 0
  br i1 %busy, label %done, label %collect
collect:
  call void @"rt_gc_collect"()
  br label %done
done:
  ret ptr %node
slow:
  %result = call ptr @"rt_obj_alloc_noinit"(i64 %size, i64 %align, i64 %type_id)
  ret ptr %result
}
"""
}

pub def llvm_char_helpers() -> String {
    """define internal i32 @"__rolang_string_char_at"(ptr %string, i32 %index) alwaysinline {
entry:
  %null = icmp eq ptr %string, null
  br i1 %null, label %fail, label %bounds
bounds:
  %payload = getelementptr i8, ptr %string, i64 32
  %data = load ptr, ptr %payload, align 8
  %len_ptr = getelementptr i8, ptr %string, i64 40
  %len = load i64, ptr %len_ptr, align 8
  %idx = sext i32 %index to i64
  %valid = icmp ult i64 %idx, %len
  br i1 %valid, label %read, label %fail
read:
  %slot = getelementptr i8, ptr %data, i64 %idx
  %byte = load i8, ptr %slot, align 1
  %value = zext i8 %byte to i32
  ret i32 %value
fail:
  ret i32 -1
}
define internal i32 @"__rolang_char_is_digit"(i32 %c) alwaysinline {
entry:
  %low = icmp sge i32 %c, 48
  %high = icmp sle i32 %c, 57
  %yes = and i1 %low, %high
  %result = zext i1 %yes to i32
  ret i32 %result
}
define internal i32 @"__rolang_char_is_alpha"(i32 %c) alwaysinline {
entry:
  %upper_low = icmp sge i32 %c, 65
  %upper_high = icmp sle i32 %c, 90
  %upper = and i1 %upper_low, %upper_high
  %lower_low = icmp sge i32 %c, 97
  %lower_high = icmp sle i32 %c, 122
  %lower = and i1 %lower_low, %lower_high
  %yes = or i1 %upper, %lower
  %result = zext i1 %yes to i32
  ret i32 %result
}
define internal i32 @"__rolang_char_is_alnum"(i32 %c) alwaysinline {
entry:
  %digit = call i32 @"__rolang_char_is_digit"(i32 %c)
  %alpha = call i32 @"__rolang_char_is_alpha"(i32 %c)
  %result = or i32 %digit, %alpha
  ret i32 %result
}
define internal i32 @"__rolang_char_is_space"(i32 %c) alwaysinline {
entry:
  %space = icmp eq i32 %c, 32
  %tab = icmp eq i32 %c, 9
  %lf = icmp eq i32 %c, 10
  %cr = icmp eq i32 %c, 13
  %a = or i1 %space, %tab
  %b = or i1 %lf, %cr
  %yes = or i1 %a, %b
  %result = zext i1 %yes to i32
  ret i32 %result
}
"""
}

// No fast-math flags: signed zero, infinities, NaNs and ambiguous quotients
// fall back to libm. Accepted remainders are exact and have the dividend sign.
pub def llvm_frem_helper() -> String {
    """define internal double @"__rolang_frem_f64"(double %a, double %b) alwaysinline {
entry:
  %q = fdiv double %a, %b
  %qabs = call double @"llvm.fabs.f64"(double %q)
  %small = fcmp olt double %qabs, 0x4330000000000000
  br i1 %small, label %fast, label %slow
fast:
  %t = call double @"llvm.trunc.f64"(double %q)
  %negative = fneg double %t
  %r = call double @"llvm.fma.f64"(double %negative, double %b, double %a)
  %rabs = call double @"llvm.fabs.f64"(double %r)
  %babs = call double @"llvm.fabs.f64"(double %b)
  %range = fcmp olt double %rabs, %babs
  %nonzero = fcmp one double %r, 0.0
  %rbits = bitcast double %r to i64
  %abits = bitcast double %a to i64
  %xor = xor i64 %rbits, %abits
  %sign = icmp sge i64 %xor, 0
  %valid_range = and i1 %range, %nonzero
  %valid = and i1 %valid_range, %sign
  br i1 %valid, label %join, label %slow
slow:
  %libm = call double @"fmod"(double %a, double %b)
  br label %join
join:
  %result = phi double [ %r, %fast ], [ %libm, %slow ]
  ret double %result
}
"""
}
