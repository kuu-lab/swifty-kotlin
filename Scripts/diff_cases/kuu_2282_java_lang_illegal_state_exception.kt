import java.lang.IllegalStateException
import java.lang.IllegalStateException as JavaIllegalStateException
import kotlin.IllegalStateException as KotlinIllegalStateException

fun main() {
    val direct: IllegalStateException = IllegalStateException("direct")
    val aliased: JavaIllegalStateException = JavaIllegalStateException("alias")
    val kotlinType: KotlinIllegalStateException = aliased

    check(direct.message == "direct")
    check(aliased.message == "alias")
    check(kotlinType is kotlin.IllegalStateException)
    println("java.lang.IllegalStateException imports resolved")
}
