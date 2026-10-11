import lifetime.producer.LifetimeOwner
fun main() {
    val owner = LifetimeOwner()
    println(owner.collectAndCheck())
    println(owner.dropAndCheck())
}
