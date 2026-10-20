import kotlin.reflect.*

fun (() -> Int).callBy(label: String): String = "custom:" + label
fun KFunction<String>.callBy(label: Int): String = "reflect:" + label
fun (() -> Int).withLabel(label: String): String = "control:" + label
fun (() -> String).callBy(args: Map<String, Any?>): String = "map:" + args.size
fun <T : String> label(): T = "generic" as T
fun value(): Int = 42
fun text(): String = "member"
fun main() {
    val ref = ::value
    val control: String = ref.withLabel("x")
    val custom: String = ref.callBy("x")
    val generic: String = ref.callBy(label())
    val member: Int = ref.callBy(emptyMap())
    val explicit: Int = ref.callBy(emptyMap<KParameter, Any?>())
    val erased: Any? = (ref as KFunction<*>).callBy(emptyMap())
    println(control); println(custom); println(generic)
    println(member); println(explicit); println(erased)
    val strings = ::text
    val fromMap: String = strings.callBy(emptyMap<String, Any?>())
    val populated: String = strings.callBy(mapOf("label" to 1))
    val memberBeforeExtension: String = strings.callBy(emptyMap())
    println(fromMap); println(populated); println(memberBeforeExtension)
    println(ref.callBy(label = "named"))
    println(ref.callBy(args = emptyMap()))
    println(strings.callBy(7))
    val maybe = if (value() == 42) ::value else null
    println(maybe?.callBy("safe"))
}
