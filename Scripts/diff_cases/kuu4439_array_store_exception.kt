open class Animal(val name: String)
class Dog(name: String) : Animal(name)
interface Speaker { fun speak(): String }
class Parrot : Speaker { override fun speak() = "squawk" }

inline fun tryStore(label: String, block: () -> Unit) {
    try {
        block()
        println("$label: stored")
    } catch (e: Exception) {
        println("$label: ${e::class.simpleName}")
    }
}

fun main() {
    val ints: Array<Number> = arrayOf(1, 2, 3)
    tryStore("c1") { (ints as Array<Any?>)[0] = "str" }
    val strs = arrayOf("a", "b")
    tryStore("c2") { (strs as Array<Any?>)[0] = 42 }
    val boxed: Array<Int> = intArrayOf(1).toTypedArray()
    tryStore("c3") { (boxed as Array<Any?>)[0] = "s2" }
    // valid stores keep working
    ints[0] = 7
    println(ints[0])
    strs[0] = "ok"
    println(strs[0])
    // Array<Any> accepts everything
    val anys: Array<Any> = arrayOf<Any>(1, "x")
    anys[0] = "str"
    anys[1] = 42
    println("${anys[0]} ${anys[1]}")
    // primitive arrays unaffected
    val ia = intArrayOf(1, 2)
    ia[0] = 9
    println(ia[0])
    // member set() spelling
    val m = arrayOf(1, 2)
    tryStore("set") { (m as Array<Any?>).set(0, "x") }
    // null into nullable component
    val ns: Array<String?> = arrayOfNulls<String?>(2)
    ns[0] = "v"
    ns[1] = null
    println("${ns[0]} ${ns[1] == null}")
    // hierarchy components
    val nums: Array<Number> = arrayOf<Number>(1, 2.5)
    nums[0] = 7
    nums[1] = 3.14
    println("${nums[0]} ${nums[1]}")
    tryStore("numstr") { (nums as Array<Any?>)[0] = "s" }
    val animals: Array<Animal> = arrayOf<Animal>(Dog("d"))
    animals[0] = Dog("d2")
    println(animals[0].name)
    tryStore("parrot") { (animals as Array<Any?>)[0] = Parrot() }
    val speakers: Array<Speaker> = arrayOf<Speaker>(Parrot())
    speakers[0] = Parrot()
    println(speakers[0].speak())
    tryStore("dogsp") { (speakers as Array<Any?>)[0] = Dog("x") }
    // primitive-component distinctions
    val chars = arrayOf('a', 'b')
    chars[0] = 'z'
    println(chars[0])
    tryStore("charint") { (chars as Array<Any?>)[0] = 1 }
    val longs = arrayOf(1L, 2L)
    longs[0] = 9L
    println(longs[0])
    tryStore("longdbl") { (longs as Array<Any?>)[0] = 1.5 }
    tryStore("longok") { (longs as Array<Any?>)[0] = 8L }
    // fill and copyInto funnel through the same store
    val strs2 = arrayOf("a", "b")
    tryStore("fill") { (strs2 as Array<Any?>).fill(42) }
    val dst: Array<Any?> = arrayOfNulls<Any?>(2)
    (arrayOf(1, 2) as Array<Any?>).copyInto(dst)
    println("${dst[0]} ${dst[1]}")
    // nested arrays accept a matching element array type
    val nested = arrayOf(arrayOf(1), arrayOf(2))
    tryStore("nested-ok-type") { (nested as Array<Any?>)[0] = arrayOf(3) }
    tryStore("nested-bad") { (nested as Array<Any?>)[0] = "not-an-array" }
}
