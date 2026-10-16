// KUU-2389: Keep the imported and fully qualified java.io.Serializable type paths working.
import java.io.Serializable

public data class Pair<out A, out B>(
    public val first: A,
    public val second: B
) : Serializable

data class QualifiedValue(val value: String) : java.io.Serializable

data class S(val value: String) : Serializable

data class PlainPair<out A, out B>(
    val first: A,
    val second: B
)

fun box(): String {
    val p = Pair(42, "OK")
    val q = Pair(42, "OK")
    if (p != q) return "Fail equals"
    if (p.hashCode() != q.hashCode()) return "Fail hashCode"
    if (p.toString() != q.toString()) return "Fail toString"

    val a = S("OK")
    val b = S("OK")
    if (a != b) return "FAIL"
    if (a.value != "OK") return "FAIL"

    val first = QualifiedValue("OK")
    val second = QualifiedValue("OK")
    if (first != second) return "Fail qualified equals"
    if (first.hashCode() != second.hashCode()) return "Fail qualified hashCode"
    if (first.toString() != second.toString()) return "Fail qualified toString"

    val plainFirst = PlainPair(42, "OK")
    val plainSecond = PlainPair(42, "OK")
    if (plainFirst != plainSecond) return "Fail plain equals"
    if (plainFirst.hashCode() != plainSecond.hashCode()) return "Fail plain hashCode"
    if (plainFirst.toString() != plainSecond.toString()) return "Fail plain toString"

    return p.second
}

fun main() {
    print(box())
}
