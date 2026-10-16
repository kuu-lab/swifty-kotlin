fun <T> choose(a: T, b: T): T = a

interface Marker
interface Render { fun render(): String }
class First : Marker, Render { override fun render() = "OK" }
class Second : Marker, Render { override fun render() = "NO" }

fun useIntersection(): String {
    val intersection = choose(First(), Second())
    return object : Render by intersection {}.render()
}

fun expectedRenderAssignment(): String {
    val render: Render = choose(First(), Second())
    return render.render()
}

fun directDelegationControl(render: Render): String =
    object : Render by render {}.render()

fun explicitTypeArgumentControl(): String =
    choose<Render>(First(), Second()).render()
