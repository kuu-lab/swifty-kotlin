import kotlin.reflect.KCallable

class CallableContractC(var v: Int) { fun f(x: Int) = x * 2 }
fun callableContractTop(a: Int) = a + 1

class CallableDefaults(var value: Int = 3) { fun add(n: Int = 7) = value + n }
fun callableDefaults(a: Int = 8, b: Int = 2) = a + b
fun callableWide(a: Int, b: Int, c: Int, d: Int) = a + b + c + d
fun callableThrows(n: Int): Int { throw IllegalArgumentException("boom") }
fun callableString(s: String = "default") = s + "!"
fun callableLong(n: Long) = n + 1L
var callableProperty = 5
const val callableConstant = 9
lateinit var callableLate: String

fun inspectCallable(callable: KCallable<Int>) {
    println(callable.call(3, 4))
    println(callable.parameters.size)
}

fun main() {
    println(CallableContractC::f.call(CallableContractC(3), 21))
    println(::callableContractTop.call(1))
    println(CallableContractC::v.isConst)
    println(CallableContractC::v.isLateinit)
    println(CallableContractC::f.parameters.size)
    println(CallableContractC::f.returnType)
    val c = CallableDefaults(20)
    println(CallableDefaults::add.call(c, 21))
    println(c::add.call(4))
    println(::callableWide.call(1, 2, 3, 4))
    val ref = ::callableDefaults
    println(ref.parameters.size)
    println(ref.parameters[0].name)
    println(ref.parameters[0].isOptional)
    println(ref.callBy(emptyMap()))
    println(ref.callBy(mapOf(ref.parameters[1] to 11)))
    val sameRef = ::callableDefaults
    println(ref.callBy(mapOf(sameRef.parameters[1] to 11)))
    val bound = c::add
    val sameBound = c::add
    println(bound.callBy(mapOf(sameBound.parameters[0] to 8)))
    val typed: KCallable<Int> = ::callableDefaults
    inspectCallable(typed)
    println(ref.call(*arrayOf<Any?>(3, 4)))
    println(ref.call(3, *arrayOf<Any?>(4)))
    println(typed.call(*arrayOf<Any?>(3, 4)))
    println(ref.isFinal)
    println(ref.isOpen)
    println(ref.isAbstract)
    println(ref.isSuspend)
    println(ref.visibility)
    println(ref.typeParameters.size)
    println(::callableConstant.isConst)
    println(::callableLate.isLateinit)
    println(CallableDefaults::value.getter.call(c))
    println(CallableDefaults::value.getter(c))
    CallableDefaults::value.setter.call(c, 40)
    println(c.value)
    CallableDefaults::value.setter(c, 41)
    println(c.value)
    println(c::value.getter.call())
    c::value.setter.call(42)
    println(c.value)
    println(::callableProperty.getter.call())
    val property = ::callableProperty
    property.setter.call(6)
    println(callableProperty)
    println(CallableDefaults::value.getter.property.name)
    val constructor = ::CallableDefaults
    println(constructor.call(9).value)
    println(constructor.callBy(emptyMap()).value)
    val string = ::callableString
    println(string.call("value"))
    println(string.callBy(emptyMap()))
    println(::callableLong.call(21L))
    val member = CallableDefaults::add
    try { member.callBy(emptyMap()) } catch (e: IllegalArgumentException) { println("required") }
    try { ref.call() } catch (e: IllegalArgumentException) { println("arity") }
    try { ref.call("wrong", 1) } catch (e: IllegalArgumentException) { println("type") }
    try { ref.call(null, 1) } catch (e: IllegalArgumentException) { println("null") }
    try { ::callableThrows.call(0) } catch (e: Throwable) { println("boom") }
}
