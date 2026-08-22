package golden.sema

class Outer {
    annotation class MyMarker(
        val message: String = "",
        val level: Level = Level.ERROR
    ) {
        enum class Level {
            WARNING,
            ERROR
        }
    }
}

@golden.sema.Outer.MyMarker
fun useMarker() {}
