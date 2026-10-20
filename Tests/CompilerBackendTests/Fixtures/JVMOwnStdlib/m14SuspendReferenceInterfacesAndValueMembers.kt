@JvmInline value class Text(val value: String)
interface Echo { suspend fun echo(v: Text): Text }
class Normal: Echo { override suspend fun echo(v: Text): Text = v }
@JvmInline value class Own(val value: Long): Echo {
    override suspend fun echo(v: Text): Text = v
    suspend fun get(v: Text = Text("member")): Text = v
}
inline fun save(v: Text, noinline block: (Text) -> Text): () -> Text = { block(v) }
inline fun cross(v: Text, crossinline block: (Text) -> Text): () -> Text = { block(v) }
suspend fun main() {
    val normal: Echo = Normal(); val own: Echo = Own(9L)
    println(normal.echo(Text("normal"))); println(own.echo(Text("own")))
    println(Own(7L).get()); println(save(Text("saved")) { it }()); println(cross(Text("cross")) { it }())
}
