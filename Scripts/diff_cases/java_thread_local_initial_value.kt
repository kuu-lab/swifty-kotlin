fun main() {
 val local = object : ThreadLocal<String>() { override fun initialValue(): String = "value" }
 println(local.get())
 println(local.get())
}
