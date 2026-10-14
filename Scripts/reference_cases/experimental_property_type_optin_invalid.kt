// KUU-2143: Kotlin 2.3.10 rejects the property read, including an inferred return.
@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class Gate
@Gate
class Experimental
@OptIn(Gate::class)
class Holder(val value: Experimental)
fun caller(holder: Holder) = holder.value
