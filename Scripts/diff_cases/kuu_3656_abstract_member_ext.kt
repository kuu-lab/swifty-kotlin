// KUU-3656: an abstract member extension declared on an interface must be
// implemented by concrete implementors — member extensions and regular members
// are distinct override families, so `Any.toString()` never satisfies an
// `Any?.toString()` requirement. This case pins the accepting side: a class
// that provides the member-extension overrides compiles, the implementations
// are inherited by subclasses, and member-extension calls dispatch to the
// overrides. The rejecting side (a class that omits the implementation) is
// pinned by CompilerCoreTests.

interface ExtContract {
    fun Any?.toString(): String
    fun Any?.describe(): String
}

open class ExtImpl : ExtContract {
    override fun Any?.toString(): String = "member-ext-tostring"
    override fun Any?.describe(): String = "member-ext:" + (this == null)

    // Member-extension call on the implicit dispatch receiver.
    fun probe(): String = (null as Any?).describe()
}

// Abstract classes may defer the requirement to subclasses.
abstract class Deferred : ExtContract

// A concrete subclass inherits the implementations without re-declaring them.
class ViaInterface : ExtImpl()

fun main() {
    println(ExtImpl().probe())
    println(ViaInterface().probe())
    println(with(ExtImpl()) { "x".describe() })
}
