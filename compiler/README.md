# Compiler

Pipeline: imports → AST → resolution → type checking → HIR → specialization
→ CFG MIR → async/ownership lowering → optimization → LLVM text → clang/linker.
main.rl calls command.rl, which parses arguments with std.cli and renders
diagnostics.rl output; the driver owns resource discovery, caching,
module artifacts and tool invocation. Every phase reports structured
diagnostics (message, file, span) rather than formatted strings.

Debug information (-g) follows statements through the pipeline: HIR records
statement and function positions (copied by specialization), the MIR builder
inserts debug_location ops, and codegen turns them into DILocations. Passes
copy these ops like any other; the MIR inliner drops the callee's.

AST/HIR/MIR definitions, visitors, rewrites and dumps are authoritative
checked-in Rolang sources. Field changes must update affected visitors,
builders, copies and dumps. A Rolang schema generator can be added later.

The runtime header, descriptors, collection handles and async ABI must remain
synchronized with runtime/abi.h, runtime/task.h and the corresponding std headers.
runtime/rolang_rt.c assembles the C implementations for linking.
Stable module identity and compatibility
live in module_abi.rl and module_artifact.rl. Version incompatible ABI changes.
Compiler and public contracts are maintained here.
