import kotlin.properties.Delegates

// KUU-2946: a `private set` on a delegated var must still route writes
// through the generated setter -> delegate.setValue, not a dead backing
// field. Writing in init then reading must return the assigned value.
class A {
    var delegate: String by Delegates.notNull()
        private set

    init { delegate = "OK" }
}

class B {
    var delegate: String by Delegates.notNull()
        private set

    init { this.delegate = "OK" }
}

var topLevel: String by Delegates.notNull()
    private set

fun box(): String {
    topLevel = "OK"
    return A().delegate + B().delegate + topLevel
}

fun main() {
    println(box())
}
