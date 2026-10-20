@Retention(AnnotationRetention.RUNTIME)
annotation class Narrow(val c: Char = '界', val b: Byte = -128, val s: Short = 32767, val chars: CharArray = ['A', '界'])
@Narrow class Sample
const val LETTER: Char = '界'
fun main() {
    val a = Sample::class.annotations[0] as Narrow
    println(a.c); println(a.b); println(a.s); println(a.chars[1]); println(LETTER)
}
