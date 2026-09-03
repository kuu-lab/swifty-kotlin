package kotlin.native

// KSP-1210: Keep the Kotlin/Native enum declaration source-backed so the
// compiler-generated entries, valueOf, and values APIs use the real nominal
// enum identity and declaration order.
@kotlin.experimental.ExperimentalNativeApi
public enum class OsFamily {
    UNKNOWN,
    MACOSX,
    IOS,
    LINUX,
    WINDOWS,
    ANDROID,
    WASM,
    TVOS,
    WATCHOS
}
