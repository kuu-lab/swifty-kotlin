// Adapted from JetBrains/Kotlin compiler/testData/codegen/box/fakeOverride/intersectionOverrideBetweenValAndVar.kt.
// Copyright JetBrains s.r.o. and Kotlin Programming Language contributors. Licensed under Apache-2.0.

abstract class A {
    abstract val x: String
}

interface B {
    var x: String
}

abstract class C : A(), B

class D(override var x: String) : C()

fun test(c: C) {
    c.x = "OK"
}

abstract class ExplicitOverride : A(), B {
    abstract override var x: String
}

class ExplicitOverrideImpl(override var x: String) : ExplicitOverride()

abstract class MutableBase {
    abstract var x: String
}

interface ReadOnlyInterface {
    val x: String
}

abstract class MutableSuperclassFirst : MutableBase(), ReadOnlyInterface

class MutableSuperclassFirstImpl(override var x: String) : MutableSuperclassFirst()

fun box(): String {
    val d = D("Fail")
    test(d)
    if (d.x != "OK") return "inherited setter"

    val explicit = ExplicitOverrideImpl("Fail")
    explicit.x = "OK"
    if (explicit.x != "OK") return "explicit override"

    val mutableSuperclass = MutableSuperclassFirstImpl("Fail")
    mutableSuperclass.x = "OK"
    if (mutableSuperclass.x != "OK") return "mutable superclass"

    return "OK"
}

fun main() {
    println(box())
}
