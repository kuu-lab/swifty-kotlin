// Runtime shim for KSP-614.
// `kk_println_any` is no longer part of the Runtime module: `kotlin.io.println`
// is implemented in Kotlin (`Sources/CompilerCore/Stdlib/kotlin/io/Console.kt`)
// on top of the single `__kk_print_raw` bridge, and the newline is appended
// there. The tests in this target exercise the runtime's boxed-value renderer,
// so they keep the old call shape through this shim.
@testable import Runtime

func kk_println_any(_ obj: UnsafeMutableRawPointer?) {
    kk_println_any(obj.map { Int(bitPattern: $0) } ?? 0)
}

func kk_println_any(_ obj: Int) {
    __kk_print_raw(obj)
    print("")
}
