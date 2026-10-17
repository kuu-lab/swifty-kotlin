package kuu2614consumer

import kotlinx.io.InternalIoApi
import kuu2614producer.internalIoApiValue

@OptIn(InternalIoApi::class)
fun main() {
    println(internalIoApiValue())
}
