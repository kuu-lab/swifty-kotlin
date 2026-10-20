lateinit var top: String
class Box {
    lateinit var text: String
    fun ready(): Boolean = this::text.isInitialized
}
fun main() {
    val box = Box()
    println(::top.isInitialized); println(box.ready())
    try { println(top) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    try { println(box.text) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    top = "top"; box.text = "member"
    println(::top.isInitialized); println(box.ready()); println(top); println(box.text)
    lateinit var local: String
    val read = { local }
    try { println(read()) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    local = "local"; println(read())
}
