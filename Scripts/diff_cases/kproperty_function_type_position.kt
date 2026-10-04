// KSP-496 follow-up: a property callable reference consumed as a plain
// *function* value — assigned to a function-typed variable, passed to a
// higher-order function, or SAM-converted to a fun interface — used to fail
// at link time with `Undefined symbols: "_v"` (the property symbol has no
// emitted function behind it, so lowering called a symbol named after the
// property itself). The SAM-conversion shape instead panicked at runtime
// with "Virtual dispatch failed: method not found in vtable/itable".

class Sample(val v: Int) {
    val doubled: Int get() = v * 2
}

class Counter(var w: Int)

object Config { val level: Int = 42 }

val topLevelConst: Int = 7
var topLevelVar: Int = 9

fun interface IntFromSample {
    fun apply(sample: Sample): Int
}

fun interface IntSupplier {
    fun get(): Int
}

fun useSam(f: IntFromSample): Int = f.apply(Sample(11))

fun useSupplier(f: IntSupplier): Int = f.get()

fun main() {
    val unbound: (Sample) -> Int = Sample::v
    println("unbound: ${unbound(Sample(1))}")

    println("map: ${listOf(Sample(1), Sample(2)).map(Sample::v)}")

    val sample = Sample(3)
    val bound: () -> Int = sample::v
    println("bound: ${bound()}")

    val customGetter: (Sample) -> Int = Sample::doubled
    println("custom getter: ${customGetter(Sample(4))}")

    val mutableMember: (Counter) -> Int = Counter::w
    println("var member: ${mutableMember(Counter(5))}")

    val singleton: () -> Int = Config::level
    println("object member: ${singleton()}")

    val topConst: () -> Int = ::topLevelConst
    println("top-level val: ${topConst()}")

    val topVar: () -> Int = ::topLevelVar
    println("top-level var: ${topVar()}")

    println("sam: ${useSam(Sample::v)}")

    println("bound sam: ${useSupplier(sample::v)}")
}
