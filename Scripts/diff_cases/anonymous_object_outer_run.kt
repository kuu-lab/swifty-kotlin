interface Delegate { fun invoke() }
class Token(val value: Int)
class Probe {
 fun run() {
  val first = Token(1)
  val second = Token(2)
  fun consume() {
   println(first.value)
   val delegate = object : Delegate {
    override fun invoke() {
     run { println(first.value); println(second.value) }
    }
   }
   delegate.invoke()
  }
  consume()
 }
}
fun main() { Probe().run() }
