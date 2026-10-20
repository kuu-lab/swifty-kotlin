package kotlin
inline infix fun <A, B> A.to(that: B): Pair<A, B> = Pair(this, that)
