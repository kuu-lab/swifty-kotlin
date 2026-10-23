// Regression for KUU-2952: every enum API surface must run the enum's
// <clinit> — entry init blocks (where `name` is already bound) followed by
// the companion initializer — on first access, including the paths that
// never reference an entry field directly (synthesized values/valueOf/
// entries bodies and the reified enumValues/enumEntries/enumValueOf).
// Adapted from JetBrains Kotlin's public box test
// enum/initEntriesInCompanionObject2.kt.

import kotlin.enums.enumEntries

var l = ""

enum class ViaValues {
    A, B;
    init { l += "ViaValues.$name;" }
    companion object { init { l += "ViaValues.CO;" } }
}

enum class ViaValueOf {
    A, B;
    init { l += "ViaValueOf.$name;" }
    companion object { init { l += "ViaValueOf.CO;" } }
}

enum class ViaEntries {
    A, B;
    init { l += "ViaEntries.$name;" }
    companion object { init { l += "ViaEntries.CO;" } }
}

enum class ViaEnumValues {
    A, B;
    init { l += "ViaEnumValues.$name;" }
    companion object { init { l += "ViaEnumValues.CO;" } }
}

enum class ViaEnumEntries {
    A, B;
    init { l += "ViaEnumEntries.$name;" }
    companion object { init { l += "ViaEnumEntries.CO;" } }
}

enum class ViaEnumValueOfThrow {
    A, B;
    init { l += "ViaEnumValueOfThrow.$name;" }
    companion object { init { l += "ViaEnumValueOfThrow.CO;" } }
}

fun box(): String {
    ViaValues.values()
    ViaValueOf.valueOf("B")
    ViaEntries.entries.size
    enumValues<ViaEnumValues>()
    enumEntries<ViaEnumEntries>()
    try {
        enumValueOf<ViaEnumValueOfThrow>("NO")
    } catch (e: Throwable) {
        l += "caught;"
    }

    val expected =
        "ViaValues.A;ViaValues.B;ViaValues.CO;" +
        "ViaValueOf.A;ViaValueOf.B;ViaValueOf.CO;" +
        "ViaEntries.A;ViaEntries.B;ViaEntries.CO;" +
        "ViaEnumValues.A;ViaEnumValues.B;ViaEnumValues.CO;" +
        "ViaEnumEntries.A;ViaEnumEntries.B;ViaEnumEntries.CO;" +
        "ViaEnumValueOfThrow.A;ViaEnumValueOfThrow.B;ViaEnumValueOfThrow.CO;caught;"
    return if (l == expected) "OK" else "fail: $l"
}

fun main() {
    println(box())
}
