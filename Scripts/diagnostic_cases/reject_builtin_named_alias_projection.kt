// EXPECT-REJECT
class Sink<in T>
typealias Double<T> = Sink<Sink<T>>
fun consume(value: Double<out Int>) {}
