class Foo {
    var x: Int = 1
        set(value) { field = value * 2 }
}

class Holder(val foo: Foo)

fun getFoo(f: Foo): Foo = f

fun main() {
    println(Foo().x)

    val f = Foo()
    println(f.x)

    println(Holder(Foo()).foo.x)

    val holder = Holder(Foo())
    println(getFoo(holder.foo).x)
}
