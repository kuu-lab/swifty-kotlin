// KUU-1205: a user type named `Element` must shadow the nested
// `CoroutineContext.Element` member leaked by the imported
// `kotlin.coroutines.CoroutineContext` declaration import — under the
// precompiled stdlib kklib the supertype `Element` and the `get(Key)`
// return-type inference used to bind to the stdlib interface instead.
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

object Key : CoroutineContext.Key<Element>
object OtherKey : CoroutineContext.Key<Element>

open class Element : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> = Key
}

class Derived : Element()

fun lookup(context: CoroutineContext): Element? = context.get(Key)

fun main() {
    val element = Element()
    val context: CoroutineContext = element
    println(lookup(context) === element)
    println(Derived().key === Key)
    println(context[OtherKey] == null)
    println(context.minusKey(Key) === EmptyCoroutineContext)
}
