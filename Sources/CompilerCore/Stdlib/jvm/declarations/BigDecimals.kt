package kotlin

import java.math.BigDecimal
import java.math.RoundingMode

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.plus(other: BigDecimal): BigDecimal = this.add(other)

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.minus(other: BigDecimal): BigDecimal = this.subtract(other)

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.times(other: BigDecimal): BigDecimal = this.multiply(other)

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.div(other: BigDecimal): BigDecimal =
    this.divide(other, RoundingMode.HALF_EVEN)

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.rem(other: BigDecimal): BigDecimal = this.remainder(other)

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.unaryMinus(): BigDecimal = this.negate()

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.inc(): BigDecimal = this.add(BigDecimal.ONE)

@kotlin.internal.InlineOnly
public inline operator fun BigDecimal.dec(): BigDecimal = this.subtract(BigDecimal.ONE)
