// KUU-3624: Generic value-class payloads must keep their nominal box at erased T boundaries.

import kotlin.jvm.JvmInline

@JvmInline
value class Augmented<T : Int>(val x: T) {
    override fun toString(): String = (x + 1).toString()
}

@JvmInline
value class AsAny<T : Any>(val value: T) {
    override fun toString(): String = "AsAny: $value"
}

@JvmInline
value class GenericFloat<T : Float>(val value: T) {
    override fun toString(): String = "GenericFloat: ${value.toString()}"
}

data class AugmentedAndAsAny(val a: Augmented<Int>, val b: AsAny<Int>)
data class NullableAugmented(val value: Augmented<Int>?)

@JvmInline
value class Foo<T : Int>(val value: T) {
    fun asResult(): T = value
}

fun <T> id(value: T): T = value
fun <T> T.idExtension(): T = this

fun <T : Int> testBoxingFromGenericReturn(value: Foo<T>): Boolean {
    id(value)
    id(value).idExtension()
    id(value).asResult()
    val first = id(value)
    val second = id(value).idExtension()
    return first.asResult() == 10 && second.asResult() == 10
}

@JvmInline
value class ComparableFoo<T : Int>(val value: T) : Comparable<ComparableFoo<T>> {
    override fun compareTo(other: ComparableFoo<T>): Int = 10
}

@JvmInline
value class ArrayFoo<T : Int>(val arg: T)

@JvmInline
value class ListFoo<T : String>(val arg: T)

interface IFoo<T> {
    fun echo(value: T): T
}

@JvmInline
value class Tagged<T : Int>(val value: T) {
    override fun toString(): String = "Tagged:$value"
}

class TaggedEcho : IFoo<Tagged<Int>> {
    override fun echo(value: Tagged<Int>): Tagged<Int> = value
}

fun <T> throughGenericInterface(foo: IFoo<T>, value: T): T = foo.echo(value)
fun <T> genericString(value: T): String = "$value"

fun box(): String {
    var failures = ""
    val augmented = Augmented(0)
    if ("$augmented" != "1") failures += "Fail 1: $augmented; "
    val asAny = AsAny(42)
    if ("$asAny" != "AsAny: 42") failures += "Fail 2: $asAny; "
    if ("$augmented and ${Augmented(1)}" != "1 and 2") failures += "Fail 3; "
    val pair = AugmentedAndAsAny(augmented, asAny)
    if (pair.toString() != "AugmentedAndAsAny(a=1, b=AsAny: 42)") failures += "Fail 4: $pair; "
    val nullableValueClass = NullableAugmented(null)
    if (nullableValueClass.toString() != "NullableAugmented(value=null)") failures += "Fail 5: $nullableValueClass; "

    if (genericString(GenericFloat(1.25f)) != "GenericFloat: 1.25") failures += "Fail 6; "

    if (!testBoxingFromGenericReturn(Foo(10))) failures += "Fail 7; "

    val comparable: Comparable<ComparableFoo<Int>> = ComparableFoo(42)
    if (comparable.compareTo(ComparableFoo(1)) != 10) failures += "Fail 8; "

    var sum = 0
    for (value in arrayOf(ArrayFoo(1), ArrayFoo(2))) sum += value.arg
    if (sum != 3) failures += "Fail 9; "

    var text = ""
    for (value in listOf(ListFoo("abc"), ListFoo("def"))) text += value.arg
    if (text != "abcdef") failures += "Fail 10; "

    val tagged = throughGenericInterface(TaggedEcho(), Tagged(7))
    if ("$tagged" != "Tagged:7") failures += "Fail 11: $tagged; "

    // KUU-3950: member reads on tagged `V<T : Int>` elements arriving
    // through erased container boundaries must unwrap to the payload
    // before the claim-site checkcast — a nominal `V` tag there throws.
    val arrayIndexed = arrayOf(ArrayFoo(3), ArrayFoo(4))[1]
    if (arrayIndexed.arg != 4) failures += "Fail 12; "

    var listSum = 0
    for (value in listOf(ArrayFoo(5), ArrayFoo(6))) listSum += value.arg
    if (listSum != 11) failures += "Fail 13; "

    val listIndexed = listOf(ArrayFoo(7), ArrayFoo(8))[0]
    if (listIndexed.arg != 7) failures += "Fail 14; "

    return if (failures.isEmpty()) "OK" else failures
}

fun main() {
    println(box())
}
