package kotlin

public abstract class Number() {
    public abstract fun toDouble(): Double
    public abstract fun toFloat(): Float
    public abstract fun toLong(): Long
    public abstract fun toInt(): Int

    @Deprecated(
        "Direct conversion to Char is deprecated. Use toInt().toChar() or Char constructor instead.\nIf you override toChar() function in your Number inheritor, it's recommended to gradually deprecate the overriding function and then remove it.\nSee https://youtrack.jetbrains.com/issue/KT-46465 for details about the migration",
        ReplaceWith("this.toInt().toChar()")
    )
    @DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.3")
    public open fun toChar(): Char = toInt().toChar()

    public abstract fun toShort(): Short
    public abstract fun toByte(): Byte
}
