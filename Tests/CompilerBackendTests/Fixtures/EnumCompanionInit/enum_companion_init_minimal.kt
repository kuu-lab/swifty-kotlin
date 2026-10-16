// KUU-2414: source-level entry and companion initialization ordering.

var enumEntryInitializers = 0
var enumCompanionInitializers = 0
var enumObservedEntries = 0
var plainEntryInitializers = 0
var regularCompanionInitializers = 0

enum class E {
    A,
    B;

    init {
        enumEntryInitializers += 1
    }

    companion object {
        init {
            enumCompanionInitializers += 1
            enumObservedEntries = enumEntryInitializers
        }
    }
}

enum class Plain {
    A,
    B;

    init {
        plainEntryInitializers += 1
    }
}

class Ordinary {
    companion object {
        init {
            regularCompanionInitializers += 1
        }

        val value = 7
    }
}

var validationResult = 0

fun main() {
    val first = E.A
    val second = E.B
    val plain = Plain.B
    val ordinaryValue = Ordinary.value
    val ordinaryValueAgain = Ordinary.value
    val ok = enumEntryInitializers == 2
        && enumCompanionInitializers == 1
        && enumObservedEntries == 2
        && plainEntryInitializers == 2
        && regularCompanionInitializers == 1
        && ordinaryValue == 7
        && ordinaryValueAgain == 7
    val divisor = if (ok) 1 else 0
    validationResult = 1 / divisor
}
