// CANDIDATE-ONLY: unqualified calls inside a nullable implicit-receiver
// scope must be rejected like kotlinc — a `String?` receiver cannot supply
// the non-null extension/member function receiver without a safe call
// (KUU-4501). Compare the diagnostics with
// kuu_4501_nullable_implicit_receiver_reject.expected.stderr.
fun String.firstCode(): Int = get(0).code

class Extensions {
    fun String.innerCode(): Int = 1
    fun viaNullableMemberExtension(s: String?): Int = with(s) { innerCode() }
}

fun viaNullableExtension(s: String?): Int = with(s) { firstCode() }
fun viaNullableMemberFn(s: String?): Char = with(s) { get(0) }
fun viaNullableMemberProp(s: String?): Int = with(s) { length }

class Box(var n: Int) {
    fun viaNullableWrite(b: Box?): Unit = with(b) { n = 1 }
}
class Handler(val run: () -> Int) {
    fun viaNullableCallableProperty(h: Handler?): Int = with(h) { run() }
}

fun main() {}
