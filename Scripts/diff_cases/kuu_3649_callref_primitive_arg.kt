fun main() {
    // Callable-reference arguments crossing into the erased
    // `Any` member-bridge slot must be boxed: `Double` non-null bits
    // (incl. -0.0, whose bit pattern equals the null sentinel) and
    // `Long.MIN_VALUE` collide with the sentinel when passed raw
    // (KUU-3649).
    val reference: (Double?) -> String = Double?::toString
    val value: Double? = -0.0
    println(reference(null))
    println(reference(-0.0))
    println(reference(value))
    println(reference(1.5))
    val ref2: (Any) -> String = Any::toString
    println(ref2(true))
    println(ref2(3.14))
    val intRef: (Int?) -> String = Int?::toString
    println(intRef(null))
    println(intRef(42))
    val boolRef: (Boolean?) -> String = Boolean?::toString
    println(boolRef(null))
    println(boolRef(true))
    val longRef: (Long?) -> String = Long?::toString
    println(longRef(Long.MIN_VALUE))
}
