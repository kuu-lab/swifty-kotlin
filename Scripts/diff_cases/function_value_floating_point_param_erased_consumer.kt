// A lambda taking a Double or Float is stored in a (Double) -> Double slot and
// later handed to a generic `(T) -> T` parameter. The generic side passes the
// argument boxed, so the function value must accept a boxed argument no matter
// how it travelled there: returned from a factory, read from a property or a
// field, passed through another function, or picked by an `if`.
fun <T> applyTo(value: T, transform: (T) -> T): T = transform(value)
fun <T> applyTo2(a: T, b: T, transform: (T, T) -> T): T = transform(a, b)

class Holder(val transform: (Double) -> Double)

val doubler: (Double) -> Double = { a -> a * 2.0 }

fun factory(): (Double) -> Double = { a -> a * 2.0 }
fun factory2(): (Double, Double) -> Double = { a, b -> a + b }
fun floatFactory(): (Float) -> Float = { a -> a * 2.0f }
fun passThrough(f: (Double) -> Double): (Double) -> Double = f
fun pick(flag: Boolean): (Double) -> Double = if (flag) { a -> a * 2.0 } else { a -> a + 1.0 }
fun capturing(k: Double): (Double) -> Double = { a -> a * k }

fun main() {
    println(applyTo(1.5, factory()))
    println(applyTo2(1.5, 2.5, factory2()))
    println(applyTo(1.5f, floatFactory()))
    println(applyTo(1.5, Holder { a -> a * 2.0 }.transform))
    println(applyTo(1.5, doubler))
    println(applyTo(1.5, passThrough { a -> a * 2.0 }))
    println(applyTo(1.5, pick(true)))
    println(applyTo(1.5, pick(false)))
    println(applyTo(1.5, capturing(3.0)))

    // The same values stay callable with their declared type.
    val viaFactory = factory()
    println(viaFactory(1.5))
    println(doubler(2.5))
    println(Holder { a -> a * 4.0 }.transform(1.5))

    // And through a local that is already known at the call.
    val local: (Double) -> Double = { a -> a * 2.0 }
    println(applyTo(1.5, local))
    println(applyTo(1.5) { a -> a * 2.0 })
}
