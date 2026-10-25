// Regression for KUU-3196. Adapted from JetBrains Kotlin's public box test:
// https://github.com/JetBrains/kotlin/blob/master/compiler/testData/codegen/box/evaluate/intrinsicConst/enumNameWithInit.kt
// `entry.name` on a compile-time-known enum entry is an intrinsic const
// evaluation on the JVM: the entry field is never loaded, so the enum's
// <clinit> (init blocks) must not run. `entry.ordinal` is NOT const-folded
// (verified against kotlinc — the entry load and <clinit> still happen), and
// binding the entry to a val is a real load that initializes.

var result = "OK"

fun <T> T.id(): T = this

enum class E {
    OK;
    init {
        result = "E"
    }
}

enum class F {
    OK;
    init {
        result = "F"
    }
}

enum class G {
    OK;
    init {
        result = "G"
    }
}

fun box(): String {
    if (E.OK.name.id() != "OK") return "Fail 1"
    if (result != "OK") return "Fail 2" // E.OK.name must not run E's init

    if (F.OK.ordinal.id() != 0) return "Fail 3"
    if (result != "F") return "Fail 4" // F.OK.ordinal loads the entry: F's init runs

    val g = G.OK // a real entry load: G's init runs
    if (result != "G") return "Fail 5"
    if (g.name != "OK") return "Fail 6"

    return "OK"
}

fun main() {
    println(box())
}
