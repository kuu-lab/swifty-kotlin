// EXPECT-REJECT
typealias Action = (Int) -> Int
fun plain(x: Any) = x is (Int) -> Int
fun negated(x: Any) = x !is (Int) -> Int
fun suspended(x: Any) = x is suspend (Int) -> Int
fun receiver(x: Any) = x is Int.() -> Int
fun suspendReceiver(x: Any) = x is suspend Int.() -> Int
fun nullable(x: Any?) = x is ((Int) -> Int)?
fun nested(x: Any) = x is (Int) -> (Int) -> Int
fun alias(x: Any) = x is Action
fun branch(x: Any) = when (x) { is (Int) -> Int -> true; else -> false }
fun negatedBranch(x: Any) = when (x) { !is suspend (Int) -> Int -> true; else -> false }
fun narrowedResult(x: (Int) -> Any) = x is (Int) -> Int
