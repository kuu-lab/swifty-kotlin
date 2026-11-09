// CANDIDATE-ONLY: unqualified member property reads, writes and
// callable-property invokes inside a nullable implicit-receiver scope are
// unsafe — kotlinc reports "only safe (?.) or non-null asserted (!!.) calls
// are allowed" for each of them (KUU-4504). Compare the diagnostics with
// kuu_4504_nullable_implicit_receiver_property_reject.expected.stderr.
class Box { var n: Int = 0; val ro: Int = 0 }
class Handler { val run: () -> Int = { 1 } }

fun viaNullableMemberProp(s: String?): Int = with(s) { length }
fun viaNullableWrite(b: Box?): Unit = with(b) { n = 1 }
fun viaNullableCompoundWrite(b: Box?): Unit = with(b) { n += 1 }
fun viaNullableCallableProperty(h: Handler?): Int = with(h) { run() }
fun viaNullableValWrite(b: Box?): Unit = with(b) { ro = 1 }

fun main() {}
