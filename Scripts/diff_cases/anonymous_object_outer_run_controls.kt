interface Delegate { fun invoke() }
class Token(val value: Int)
class RenamedProbe {
 fun perform() {
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
class ExplicitProbe {
 fun run() {
  val first = Token(1)
  val second = Token(2)
  fun consume() {
   println(first.value)
   val delegate = object : Delegate {
    override fun invoke() {
     kotlin.run { println(first.value); println(second.value) }
    }
   }
   delegate.invoke()
  }
  consume()
 }
}
class DirectProbe {
 fun run() { run { println(3) } }
}
class ApplicableProbe {
 fun run(block: () -> Unit) { println(4); block() }
 fun perform() {
  fun consume() {
   val delegate = object : Delegate {
    fun run(block: () -> Unit) { println(4); block() }
    override fun invoke() {
     run { println(5) }
     this@ApplicableProbe.run { println(7) }
    }
   }
   delegate.invoke()
  }
  consume()
 }
}
fun choose(value: Int): Int = -1
class ApplicableOuterProbe {
 fun choose(value: Int): Int = value + 20
 fun perform() {
  fun consume() {
   val delegate = object : Delegate {
    override fun invoke() { println(choose(1)) }
   }
   delegate.invoke()
  }
  consume()
 }
}
class NestedProbe {
 fun run() {
  val first = Token(6)
  fun consume() {
   val outer = object : Delegate {
    override fun invoke() {
     fun nested() {
      val inner = object : Delegate {
       override fun invoke() { run { println(first.value) } }
      }
      inner.invoke()
     }
     nested()
    }
   }
   outer.invoke()
  }
  consume()
 }
}
fun main() {
 RenamedProbe().perform()
 ExplicitProbe().run()
 DirectProbe().run()
 ApplicableProbe().perform()
 ApplicableOuterProbe().perform()
 NestedProbe().run()
}
