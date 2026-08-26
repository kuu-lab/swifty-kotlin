package golden.sema

fun returnUnit(): Unit = Unit

fun exerciseUnitToString(): String {
    val direct: Unit = Unit
    val erased: Any = direct
    return direct.toString() + "|" +
        erased.toString() + "|" +
        "$direct" + "|" +
        returnUnit().toString()
}

fun unitIdentityAndType(): Boolean =
    Unit === Unit && returnUnit() === Unit && (returnUnit() is Unit)
