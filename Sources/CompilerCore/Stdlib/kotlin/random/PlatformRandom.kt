package kotlin.random

import java.util.Random as JavaUtilRandom
import kotlin.internal.KsSymbolName

private external fun __kk_random_seed_entropy(): Long

internal fun platformDefaultRandom(): Random = Random(__kk_random_seed_entropy())

@KsSymbolName("__kk_random_nextInt_rangeObject")
private external fun __kk_random_nextInt_rangeObject(random: Random, range: IntRange): Int

@KsSymbolName("__kk_random_nextLong_rangeObject")
private external fun __kk_random_nextLong_rangeObject(random: Random, range: LongRange): Long

public fun Random.nextInt(range: IntRange): Int = __kk_random_nextInt_rangeObject(this, range)

public fun Random.nextLong(range: LongRange): Long = __kk_random_nextLong_rangeObject(this, range)

public fun java.util.Random.asKotlinRandom(): kotlin.random.Random = this.delegate

public fun Random.asJavaRandom(): java.util.Random = JavaUtilRandom(this)
