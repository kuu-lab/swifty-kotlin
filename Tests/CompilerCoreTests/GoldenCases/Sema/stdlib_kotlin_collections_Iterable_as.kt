package golden.sema

fun iterableAsIterable(values: Iterable<String?>): Iterable<String?> = values.asIterable()

fun listAsIterable(values: List<Int>): Iterable<Int> = values.asIterable()

fun setAsIterable(values: Set<Int?>): Iterable<Int?> = values.asIterable()

fun genericAsIterable(values: List<String>): Iterable<String> = values.asIterable()
