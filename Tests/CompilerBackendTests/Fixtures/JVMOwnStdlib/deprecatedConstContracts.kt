@Deprecated("top") const val top = 1
@Deprecated("private-top") private const val privateTop = 2
class ConstBox { companion object {
    @Deprecated("class") const val value = 3
    @Deprecated("private-class") private const val secret = 4
} }
interface ConstFace { companion object {
    @Deprecated("interface") const val value = 5
    @Deprecated("private-interface") private const val secret = 6
} }
object ConstObject {
    @Deprecated("object") const val value = 7
    @Deprecated("private-object") private const val secret = 8
}
@Suppress("DEPRECATION")
fun main() { println(top); println(ConstBox.value); println(ConstFace.value); println(ConstObject.value) }
