// KUU-4125: the `String` String-HOF special path pins `map`/`mapIndexed`/
// `mapNotNull` lambdas to `(Char) -> Any?`, which used to feed overload
// resolution an `Any?` lower bound for `R` and conflict with the expected
// `List<R>` result type (KSWIFTK-TYPE-0001 Conflicting bounds). The lambda
// body's inferred return type must drive `R`.
fun <R> onString(transform: (Char) -> R, s: String): List<R> = s.map { transform(it) }
fun echo(s: String): List<Char> = s.map { it }
fun codes(s: String): List<Int> = s.map { it.code }
fun indexed(s: String): List<Int> = s.mapIndexed { i, c -> i + c.code }
