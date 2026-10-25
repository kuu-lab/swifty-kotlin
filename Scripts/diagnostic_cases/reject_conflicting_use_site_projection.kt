// EXPECT-REJECT
fun consume(value: Producer<in Int>) {}
class Producer<out T>
