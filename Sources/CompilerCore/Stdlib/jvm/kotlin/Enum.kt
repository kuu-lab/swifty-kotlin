package kotlin

public inline fun <reified T : Enum<T>> enumValues(): Array<T> =
    throw IllegalStateException("enumValues is expanded by the compiler")
