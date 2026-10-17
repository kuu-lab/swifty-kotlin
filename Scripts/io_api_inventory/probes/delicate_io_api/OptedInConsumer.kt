package delicateprobe.consumer

import delicateprobe.delicateOperation
import kotlinx.io.DelicateIoApi

@OptIn(DelicateIoApi::class)
fun main() {
    println(delicateOperation())
}
