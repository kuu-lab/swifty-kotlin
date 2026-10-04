// KSP-613: `runCatching` must resolve through ordinary call resolution
// (kotlin.runCatching declared in the bundled stdlib), including explicit type
// arguments and callable references.

fun answer(): Int = 42

fun boom(): Int = throw IllegalStateException("boom")

fun main() {
    // 1. Basic lambda block
    val ok = runCatching { answer() }
    println("ok isSuccess=${ok.isSuccess} value=${ok.getOrNull()}")

    // 2. Failing block
    val bad = runCatching { boom() }
    println("bad isFailure=${bad.isFailure} message=${bad.exceptionOrNull()?.message}")

    // 3. Callable reference argument
    val viaRef = runCatching(::answer)
    println("viaRef=${viaRef.getOrDefault(-1)}")

    val viaRefFail = runCatching(::boom)
    println("viaRefFail=${viaRefFail.getOrDefault(-1)}")

    // 4. Explicit type argument
    val explicit = runCatching<String> { "explicit" }
    println("explicit=${explicit.getOrNull()}")

    // 5. Unit-returning block
    val unitResult = runCatching { println("side effect") }
    println("unitResult isSuccess=${unitResult.isSuccess}")

    // 6. Nullable inner type
    val nullable = runCatching { null as String? }
    println("nullable=${nullable.getOrNull()}")

    // 7. Nested runCatching
    val nested = runCatching { runCatching { 7 }.getOrThrow() }
    println("nested=${nested.getOrNull()}")

    // 8. fold over the produced Result, including a capturing onFailure callback
    val tag = "t"
    println("folded=" + runCatching { 5 }.fold({ v -> "v$v" }, { e -> "e${e.message}" }))
    println("foldedFail=" + runCatching { boom() }.fold({ v -> "v$v" }, { e -> "e${e.message}" }))
    println("foldedCapture=" + runCatching { boom() }.fold({ v -> tag + v }, { e -> tag + e.message }))
}
