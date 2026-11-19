package kotlin

import java.math.BigDecimal
import java.math.RoundingMode

public inline operator fun BigDecimal.plus(other: BigDecimal): BigDecimal = this.add(other)

public inline operator fun BigDecimal.minus(other: BigDecimal): BigDecimal = this.subtract(other)

public inline operator fun BigDecimal.times(other: BigDecimal): BigDecimal = this.multiply(other)

public inline operator fun BigDecimal.div(other: BigDecimal): BigDecimal =
    this.divide(other, RoundingMode.HALF_EVEN)

public inline operator fun BigDecimal.rem(other: BigDecimal): BigDecimal = this.remainder(other)

public inline operator fun BigDecimal.unaryMinus(): BigDecimal = this.negate()

public inline operator fun BigDecimal.inc(): BigDecimal = this.add(BigDecimal.ONE)

public inline operator fun BigDecimal.dec(): BigDecimal = this.subtract(BigDecimal.ONE)
