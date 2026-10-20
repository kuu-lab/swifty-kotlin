package kotlin.coroutines.jvm.internal

// Clear a coroutine spill reference once the resumed value has been read.
fun nullOutSpilledVariable(value: Any?): Any? = null
