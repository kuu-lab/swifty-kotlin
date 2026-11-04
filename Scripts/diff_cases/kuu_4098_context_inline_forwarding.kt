// Regression: an `inline` parameter of a context-receiver function type must
// forward to another `inline` callee however the target spells the same
// input list — `C.() -> A`, `(C) -> A`, and `context(C) () -> A` share one
// effective function shape (KUU-4098). Before the fix, generic candidates
// rejected the context spelling during constraint decomposition, failing
// overload resolution and cascading into KSWIFTK-SEMA-0449 on every
// forwarded argument (arrow-core's Raise DSL hits this via import aliases).

interface Raise<in E> {
    fun raise(error: E): Nothing
}

inline fun <Error, OtherError> Raise<Error>.withError(
    transform: (OtherError) -> Error,
    block: Raise<OtherError>.() -> Unit
) {
    val receiver = object : Raise<OtherError> {
        override fun raise(error: OtherError): Nothing = throw RuntimeException("raise")
    }
    receiver.block()
}

inline fun <Error, OtherError> Raise<Error>.withErrorPlain(
    transform: (OtherError) -> Error,
    block: (Raise<OtherError>) -> Unit
) {
    val receiver = object : Raise<OtherError> {
        override fun raise(error: OtherError): Nothing = throw RuntimeException("raise")
    }
    block(receiver)
}

inline fun <Error, OtherError> Raise<Error>.withErrorCtx(
    transform: (OtherError) -> Error,
    block: context(Raise<OtherError>) () -> Unit
) {
    val receiver = object : Raise<OtherError> {
        override fun raise(error: OtherError): Nothing = throw RuntimeException("raise")
    }
    with(receiver) { block() }
}

inline fun <Error, OtherError> Raise<Error>.useCtx(
    transform: (OtherError) -> Error,
    block: context(Raise<OtherError>) () -> Unit
) {
    this.withError(transform, block)
    this.withErrorPlain(transform, block)
}

inline fun <Error, OtherError> Raise<Error>.useExt(
    transform: (OtherError) -> Error,
    block: Raise<OtherError>.() -> Unit
) {
    this.withErrorCtx(transform, block)
}

fun main() {
    val raise = object : Raise<String> {
        override fun raise(error: String): Nothing = throw RuntimeException(error)
    }
    raise.useCtx({ s: String -> "id:$s" }, context(r: Raise<String>) fun() { println("ctx block ran") })
    raise.useExt({ s: String -> "id:$s" }, { println("ext block ran") })
}
