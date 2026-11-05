// EXPECT-REJECT
// KUU-4291: Kotlin 2.4 context parameters must be named (`name:`) or
// anonymous (`_:`); bare `context(T)` elements are rejected per element.
interface R
context(R)
fun single() {}
context(R, R)
fun multi() {}
context(_: R)
fun anon() {}
context(named: R)
fun named() {}
