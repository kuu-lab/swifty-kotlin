package golden.sema

fun makeShort(): KotlinVersion = KotlinVersion(2, 1)

fun makeFull(): KotlinVersion = KotlinVersion(2, 1, 20)

fun current(): KotlinVersion = KotlinVersion.CURRENT

fun maxComponent(): Int = KotlinVersion.MAX_COMPONENT_VALUE

fun main() {
    println(makeShort().toString())
    println(makeFull().toString())
    println(current().toString())
    println(maxComponent())
}
