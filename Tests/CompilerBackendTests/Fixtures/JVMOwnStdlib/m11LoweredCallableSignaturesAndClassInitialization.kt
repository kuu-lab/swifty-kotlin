@JvmInline value class Token(val n: Int)
abstract class Base { abstract fun echo(v: Token): Token }
class Impl: Base() { override fun echo(v: Token): Token = v }
class Cold { companion object { init { println("INIT") } } }
fun echo(v: Token): Token = v
fun Token.many(p0: Int = 0, p1: Int = 1, p2: Int = 2, p3: Int = 3, p4: Int = 4, p5: Int = 5, p6: Int = 6, p7: Int = 7, p8: Int = 8, p9: Int = 9, p10: Int = 10, p11: Int = 11, p12: Int = 12, p13: Int = 13, p14: Int = 14, p15: Int = 15, p16: Int = 16, p17: Int = 17, p18: Int = 18, p19: Int = 19, p20: Int = 20, p21: Int = 21, p22: Int = 22, p23: Int = 23, p24: Int = 24, p25: Int = 25, p26: Int = 26, p27: Int = 27, p28: Int = 28, p29: Int = 29, p30: Int = 30, p31: Int = 31): Token = Token(n + p31)
@JvmName("renamed") fun named(n: Int): Int = n + 1
fun main() {
    println(Cold::class.simpleName)
    val f = ::echo; println(f(Token(3))); println(f.call(Token(4)))
    val ctor = ::Token; println(ctor.name); println(ctor(5)); println(ctor.call(6))
    val renamed = ::named; println(renamed(8)); println(renamed.name)
    val base: Base = Impl(); println(base.echo(Token(7))); println(Token(1).many())
}
