// EXPECT-REJECT
// KUU-3091: constructor is an ordinary name in executable blocks.
fun main() {
    constructor()
    @Suppress("x") constructor()
}
