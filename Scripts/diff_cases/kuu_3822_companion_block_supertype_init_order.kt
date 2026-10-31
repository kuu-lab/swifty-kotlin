// KOTLINC_FLAGS: -Xcompanion-blocks-and-extensions
// KUU-3822: initializing a class whose companion scope is a `companion {}`
// block first initializes the supertype's companion blocks (JLS 12.4.1
// superclass-chain-first order), exactly like named companion objects.

var initOrder = ""

open class Parent {
    companion {
        val parentProp1: String = run { initOrder += "P1 "; "parent1" }
        val parentProp2: String = run { initOrder += "P2 "; "parent2" }
    }
}

class Child : Parent() {
    companion {
        val childProp1: String = run { initOrder += "C1 "; "child1" }
        val childProp2: String = run { initOrder += "C2 "; "child2" }
    }
}

fun main() {
    println(Child.childProp1)
    println(initOrder)
}
