import java.util.Date

fun main() {
    println(Date(0).getTime())
    println(Date(1234567890123L).getTime())
    println(Date().getTime() > 0L)
}
