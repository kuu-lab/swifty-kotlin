// KOTLINC_FLAGS: -Xreturn-value-checker=full

@MustUseReturnValues()
class AnnotatedScope

fun marker(value: MustUseReturnValues?): Int = if (value == null) 0 else 1

fun main() {
    println(marker(null))
}
