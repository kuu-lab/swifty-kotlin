import kotlin.reflect.KParameter

fun topFn(a: Int, b: String = "x", vararg rest: Long) = a + rest.size

class KindHost(val marker: Int = 0) {
    fun member(x: Int) = x + marker
}

fun String.topExt(y: Int) = length + y

fun describe(p: KParameter): String =
    "${p.index}:${p.name}:${p.kind}:opt=${p.isOptional}:vararg=${p.isVararg}"

fun main() {
    println(KParameter.Kind.INSTANCE)
    println(KParameter.Kind.EXTENSION_RECEIVER)
    println(KParameter.Kind.VALUE)
    println(KParameter.Kind.VALUE.ordinal)
    println(KParameter.Kind.INSTANCE.name)
    for (p in ::topFn.parameters) {
        println(describe(p))
    }
    for (p in KindHost::member.parameters) {
        println(describe(p))
    }
    for (p in String::topExt.parameters) {
        println(describe(p))
    }
    val kind = ::topFn.parameters[0].kind
    println(kind == KParameter.Kind.VALUE)
    println(kind == KParameter.Kind.INSTANCE)
}
