import kotlin.jvm.JvmName

class Probe {
    var size = 1
        @JvmName("readSize") get
        @JvmName("writeSize") set
}

fun main() {
    val probe = Probe()
    println(probe.size)
    probe.size = 4
    println(probe.size)
}
