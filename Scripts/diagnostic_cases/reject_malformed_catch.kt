// EXPECT-REJECT
fun main() {
    try { println(1) } catch { }
    try { println(1) } catch (e: Exception, f: Exception) { }
}
