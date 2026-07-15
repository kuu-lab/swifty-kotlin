// SKIP-DIFF (DEBT-DIFF-001): kotlinc rejects expect/actual unless split across common/platform files with -Xcommon-sources, which this single-file harness cannot express; kswiftc also has independent expect/actual bugs. See docs/diff-skip-inventory.md.
package diff.kmp

expect fun <T> identity(value: T): T
actual fun <T> identity(value: T): T = value

expect val platformName: String
actual val platformName: String = "kswift"

fun main() {
    println(platformName)
    println(identity(42))
}
