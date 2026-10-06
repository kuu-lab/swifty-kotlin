import kotlinx.io.DelicateIoApi
import kotlinx.io.EOFException
import kotlinx.io.IOException
import kotlinx.io.InternalIoApi
import kotlinx.io.SystemLineSeparator
import kotlinx.io.UnsafeIoApi

@DelicateIoApi
fun delicateValue(): Int = 7

@InternalIoApi
fun internalValue(): Int = 8

@UnsafeIoApi
fun unsafeValue(): Int = 9

@OptIn(DelicateIoApi::class, InternalIoApi::class, UnsafeIoApi::class)
fun main() {
    println(delicateValue() + internalValue() + unsafeValue())
    println(SystemLineSeparator == "\n")
    println(IOException().message)
    println(IOException("message").message)
    println(EOFException().message)
    println(EOFException("end").message)
    println(EOFException("end") is IOException)
}
