class Bar {
    inline operator fun invoke(f: () -> String) { f() }
}

class Baz

class Foo {
    val bar = Bar()
    val baz = Baz()
}

inline operator fun Baz.invoke(f: () -> String) { f() }

fun testMember(foo: Foo): String {
    foo.bar { return "member" }
    return "Fail-member"
}

fun testExtension(foo: Foo): String {
    foo.baz { return "extension" }
    return "Fail-extension"
}

fun main() {
    println(testMember(Foo()))
    println(testExtension(Foo()))
}
