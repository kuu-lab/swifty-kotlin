// KUU-3924: upstream kotlinx-io 0.9.1 declares
// `internal const val REPLACEMENT_CHARACTER: Char = '\ufffd'` in
// kotlinx.io.internal (-Utf8.kt), and upstream Utf8Test.kt consumes it via
// REPLACEMENT_CHARACTER.toString() under INVISIBLE_MEMBER/INVISIBLE_REFERENCE
// suppressions. The bundled port must expose the same declaration so the
// import resolves identically to the real kotlinx-io jar.
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
import kotlinx.io.internal.REPLACEMENT_CHARACTER

fun main() {
    println(REPLACEMENT_CHARACTER)
    println(REPLACEMENT_CHARACTER.toString())
    println(REPLACEMENT_CHARACTER.code)
}
