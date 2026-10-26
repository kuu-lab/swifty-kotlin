/*
 * Unsafe linear-memory access API for the wasm target, mirroring the
 * Kotlin/Wasm kotlin.wasm.unsafe surface.
 *
 * The runtime implementation is part of the interop layer (M5+): while the
 * backend lowers through linear memory, allocator calls are runtime stubs —
 * they exist so wasm-target user code type-checks against the same surface
 * Kotlin/Wasm exposes.
 */

package kotlin.wasm.unsafe

/**
 * Allocates raw linear-memory bytes on the wasm heap.
 *
 * `Pointer` is an opaque linear-memory address; the compiler backend will
 * substitute a real bump/gc-backed allocator once the WasmGC memory model
 * lands — treat the value as opaque.
 */
public interface Pointer

/**
 * Raw wasm linear-memory allocator.
 */
public interface MemoryAllocator {
    /**
     * Allocates [size] bytes and returns a pointer to them.
     * The returned memory is uninitialized.
     */
    public fun allocate(size: Int): Pointer
}

/**
 * An allocator whose whole region is freed at once when [withMemoryScoped]
 * returns — the Kotlin/Wasm "scoped memory" pattern.
 */
public interface ScopedMemoryAllocator : MemoryAllocator

/**
 * Runs [block] with a fresh [ScopedMemoryAllocator], freeing every
 * allocation it made when the block returns.
 */
public fun <T> withMemoryScoped(block: (ScopedMemoryAllocator) -> T): T {
    TODO("withMemoryScoped is provided by the wasm runtime")
}
