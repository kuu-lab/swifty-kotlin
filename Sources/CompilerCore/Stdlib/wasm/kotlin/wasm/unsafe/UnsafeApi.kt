package kotlin.wasm.unsafe

public interface Pointer

public interface MemoryAllocator {
    public fun allocate(size: Int): Pointer
}

public interface ScopedMemoryAllocator : MemoryAllocator

public fun <T> withMemoryScoped(block: (ScopedMemoryAllocator) -> T): T {
    TODO("withMemoryScoped is provided by the wasm runtime")
}
