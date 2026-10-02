package golden.sema

@Suppress("DEPRECATION_ERROR")
fun constructExplicit(value: Int): kotlin.native.concurrent.AtomicInt =
    kotlin.native.concurrent.AtomicInt(value)
