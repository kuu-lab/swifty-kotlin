@JvmInline value class I(val value: Int)
@JvmInline value class S(val value: String)
@JvmInline value class N(val value: String?)
@JvmInline value class Outer(val value: I)
@JvmInline value class Deep(val value: Outer)
@JvmInline value class Text(val value: S)
@JvmInline value class Maybe(val value: S?)
@JvmInline value class NullText(val value: N)
@JvmInline value class Boxed(val value: N?)
fun echo(v: Deep): Deep = v
fun text(v: Text?): Text? = v
fun maybe(v: Maybe?): Maybe? = v
fun main() {
    val v = Deep(Outer(I(21))); println(echo(v)); println(v.value.value.value)
    println(v.hashCode()); println(v == Deep(Outer(I(21))))
    val any: Any = v; println(any); println(any == v)
    println(text(null)); println(text(Text(S("ok"))))
    println(maybe(null)); println(maybe(Maybe(null))); println(maybe(Maybe(S("yes"))))
    println(NullText(N(null))); println(Boxed(null)); println(Boxed(N(null)))
    val read = { v.value.value.value }; println(read())
}
