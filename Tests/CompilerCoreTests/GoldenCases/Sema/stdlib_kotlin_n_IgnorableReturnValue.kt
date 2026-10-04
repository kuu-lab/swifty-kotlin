package golden.sema

@IgnorableReturnValue
fun ignored(): Int = 1

fun user() {
    ignored()
}
