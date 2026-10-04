import kotlin.ranges.CharProgression.Companion as CharProgressionFactory

fun implicitCharProgressionCompanion(): CharProgression.Companion = CharProgression

fun explicitCharProgressionCompanion(): CharProgression.Companion = CharProgression.Companion

fun importedCharProgressionCompanion(): CharProgression.Companion = CharProgressionFactory

fun progressionFromCompanion(factory: CharProgression.Companion): CharProgression =
    factory.fromClosedRange('a', 'g', 2)
