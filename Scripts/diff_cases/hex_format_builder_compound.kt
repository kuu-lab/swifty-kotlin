// Scratch regression, Kotlin/JVM reference fixed independently.
class SetterControl {
    var calls: Int = 0
    var value: Int = 1
        set(v) {
            calls += 1
            field = v * 2
        }
    var plain: Int = 0
    fun update() {
        value += 1
        value++
        plain += 3
    }
}
fun main() {
    HexFormat {
        bytes {
            bytesPerLine = 1
            bytesPerGroup = 1
            bytePrefix = "["
            byteSuffix = "]"
            byteSeparator = ":"
            try { bytesPerLine -= 1 } catch (failure: IllegalArgumentException) {
                println("line-compound")
            }
            println(bytesPerLine)
            try { bytesPerGroup-- } catch (failure: IllegalArgumentException) {
                println("group-postfix")
            }
            println(bytesPerGroup)
            try { bytePrefix += "\n" } catch (failure: IllegalArgumentException) {
                println("prefix-compound")
            }
            println(bytePrefix)
            try { byteSuffix += "\r" } catch (failure: IllegalArgumentException) {
                println("suffix-compound")
            }
            println(byteSuffix)
            try { byteSeparator += "\r" } catch (failure: IllegalArgumentException) {
                println("separator-compound")
            }
            println(byteSeparator)
            groupSeparator += "\n"
            println(groupSeparator.endsWith("\n"))
        }
    }
    val control = SetterControl()
    control.update()
    println(control.value)
    println(control.calls)
    println(control.plain)
}
