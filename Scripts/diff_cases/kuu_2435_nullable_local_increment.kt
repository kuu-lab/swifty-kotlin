class MyClass

operator fun MyClass?.inc(): MyClass? = null

fun box() : String {
    var i : MyClass?
    i = MyClass()
    val j = ++i
    return if (j == null && null == i) "OK" else "fail i = $i j = $j"
}

fun nullableInitializerControl(): String {
    var value: MyClass? = MyClass()
    val result = ++value
    return if (result == null && value == null) "OK" else "FAIL initializer"
}

fun nullableNullInitializerControl(): String {
    var value: MyClass? = null
    value = MyClass()
    val result = ++value
    return if (result == null && value == null) "OK" else "FAIL null initializer"
}

class NonNullableClass(val value: Int) {
    operator fun inc(): NonNullableClass = NonNullableClass(value + 1)
}

fun nonNullableControl(): String {
    var value = NonNullableClass(0)
    val result = ++value
    return if (result.value == 1 && value.value == 1) "OK" else "FAIL non-nullable"
}

fun main() {
    println(box())
    println(nullableInitializerControl())
    println(nullableNullInitializerControl())
    println(nonNullableControl())
}
