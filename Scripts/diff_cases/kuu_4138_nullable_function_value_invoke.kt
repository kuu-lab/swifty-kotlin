// CANDIDATE-ONLY: invoking a possibly-null function value without
// `?.invoke`/`!!` is an unsafe call — kotlinc rejects `f()` on
// `(() -> Unit)?` ("reference has a nullable type ... Use explicit
// '?.invoke'") and `f.invoke()`/`c(t)` on `F : ((T) -> R)?` the same way.
// KSwiftK accepted all of them (KUU-4138); the rejections are pinned by
// kuu_4138_nullable_function_value_invoke.expected.stderr.
fun direct(f: (() -> Unit)?) = f()
fun explicitInvoke(f: (() -> Unit)?) = f.invoke()
fun <T, R, F : ((T) -> R)?> boundCall(t: T, c: F): R = c(t)
fun <T, R, F : ((T) -> R)?> boundInvoke(t: T, c: F): R = c.invoke(t)
fun main() { }
