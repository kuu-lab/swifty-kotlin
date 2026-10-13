// CANDIDATE-ONLY: this single-file harness cannot model common/platform source sets for JVM kotlinc; compare the candidate's expect/actual runtime output directly.
package diff.kmp

expect fun <T> identity(value: T): T
actual fun <T> identity(value: T): T = value

expect val platformName: String
actual val platformName: String = "kswift"

fun main() {
    println(platformName)
    println(identity(42))
}
