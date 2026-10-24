// EXPECT-REJECT
class NoParent {
    override fun f() = 1
}

open class EmptyParent
class Child : EmptyParent() {
    override fun g() = 2
}

class PropertyChild {
    override val x = 3
}
