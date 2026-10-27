// EXPECT-REJECT
package user.channels

class Channel<T>

suspend fun <T> Channel<T>.receive(): T = throw Exception()

fun invalid(ch: Channel<Int>) {
    ch.receive()
}
