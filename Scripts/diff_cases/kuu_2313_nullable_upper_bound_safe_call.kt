// KUU-2313: A safe-call and a successful null check expose the non-null view
// of a type parameter whose upper bound is nullable, while an unguarded call
// remains invalid (covered by the Sema regression test).

fun <T : Number?> convert(value: T): Int? = value?.toInt()

fun <T : Number?> convertAfterNullCheck(value: T): Int? =
    if (value == null) null else value.toInt()

fun box(): String {
    if (convert<Int?>(null) != null) return "FAIL"
    if (convertAfterNullCheck<Int?>(null) != null) return "FAIL"
    if (convert<Int?>(42) != 42) return "FAIL"
    if (convertAfterNullCheck<Int?>(42) != 42) return "FAIL"
    return "OK"
}

fun main() {
    print(box())
}
