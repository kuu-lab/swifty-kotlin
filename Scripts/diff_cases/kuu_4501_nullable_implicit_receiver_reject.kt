// CANDIDATE-ONLY: unqualified calls inside a nullable implicit-receiver
// scope must be rejected like kotlinc — a `String?` receiver cannot supply
// the non-null extension/member function receiver without a safe call
// (KUU-4501). Member property reads/writes and callable-property invokes on
// nullable implicit receivers are tracked separately. Compare the
// diagnostics with
// kuu_4501_nullable_implicit_receiver_reject.expected.stderr.
fun String.firstCode(): Int = get(0).code

class Extensions {
    fun String.innerCode(): Int = 1
    fun viaNullableMemberExtension(s: String?): Int = with(s) { innerCode() }
}

fun viaNullableExtension(s: String?): Int = with(s) { firstCode() }
fun viaNullableMemberFn(s: String?): Char = with(s) { get(0) }

fun main() {}
