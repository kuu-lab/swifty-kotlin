class Context(val prefix: String)

context(ctx: Context)
fun run() {
    println(message())
    println(secondary())
}

context(ctx: Context)
fun message(): String = ctx.prefix + " hello"

context(ctx: Context)
fun secondary(): String = ctx.prefix.uppercase()

fun main() {
    with(Context("hi")) {
        run()
    }
}
