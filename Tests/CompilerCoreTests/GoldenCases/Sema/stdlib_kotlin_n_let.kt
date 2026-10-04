package golden.sema

fun useLet(): Int = 41.let { it + 1 }

fun useNullableLet(value: String?): Int? = value?.let { it.length }

fun useNamedLet(): String = "hello".let { value -> value + "!" }
