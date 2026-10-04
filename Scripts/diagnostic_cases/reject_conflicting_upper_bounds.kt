// EXPECT-REJECT
fun <T> conflicting(value: T): T where T : Int, T : String = value
