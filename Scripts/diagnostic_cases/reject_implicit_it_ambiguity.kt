// EXPECT-REJECT
fun process(block: (Int) -> String) = block(1)
fun process(block: (String) -> Int) = block("a")

val result = process { it }
