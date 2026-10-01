# Development plan

Each phase must remain buildable with a compatible Genesis Compiler.

1. **Compiler foundation:** Genesis builds, compiler maintenance and relocatable
   installation. Establish supported platforms and toolchain versions.
2. **Standard library contracts:** specify errors, ownership, mutability,
   encoding and platform behavior. Stabilize collections, bytes/UTF-8 text,
   Result-based I/O, paths and processes first. Add JSON/TOML, time, randomness,
   networking and serialization. C primitives can stay behind
   typed Rolang APIs until their replacements are ready.
3. **Project management in Rolang:** add a separate tools/rolang entry point for
   new/init/build/run/check/test. Reuse the native CompilationDriver. Implement
   manifests, workspace/target graphs, path dependencies and lockfiles first.
4. **Packages/distribution:** Git and registry dependencies, version resolution,
   checksummed archives, offline installation and reproducible release bundles.
   Release metadata identifies compiler, runtime and module ABI versions.
5. **Editor/platform support:** LSP uses native source/symbol/type tables.
   Add platform adapters and cross-target execution checks before promising
   broader target support.

These are planned phases, not features claimed by the initial repository.
