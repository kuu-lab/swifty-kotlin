package golden.sema

@MustUseReturnValues()
class AnnotatedScope

fun construct(): MustUseReturnValues = MustUseReturnValues()

fun marker(value: MustUseReturnValues?): Int = if (value == null) 0 else 1

fun main() {
    construct()
    println(marker(null))
}
