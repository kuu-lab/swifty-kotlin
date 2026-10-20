package kotlin

/** A pair with the JVM ABI used by Kotlin and Java consumers. */
public data class Pair<out A, out B>(public val first: A, public val second: B) : java.io.Serializable {
    override fun toString(): String = "($first, $second)"
}

public infix fun <A, B> A.to(that: B): Pair<A, B> = Pair(this, that)
