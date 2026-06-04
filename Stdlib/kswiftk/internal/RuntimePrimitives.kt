package kswiftk.internal

@KSwiftKRuntimeName("kk_int_countOneBits")
external fun __intCountOneBits(value: Int): Int

@KSwiftKRuntimeName("kk_int_countLeadingZeroBits")
external fun __intCountLeadingZeroBits(value: Int): Int

@KSwiftKRuntimeName("kk_int_countTrailingZeroBits")
external fun __intCountTrailingZeroBits(value: Int): Int

@KSwiftKRuntimeName("kk_int_highestOneBit")
external fun __intHighestOneBit(value: Int): Int

@KSwiftKRuntimeName("kk_int_lowestOneBit")
external fun __intLowestOneBit(value: Int): Int

@KSwiftKRuntimeName("kk_int_rotateLeft")
external fun __intRotateLeft(value: Int, distance: Int): Int

@KSwiftKRuntimeName("kk_int_rotateRight")
external fun __intRotateRight(value: Int, distance: Int): Int

@KSwiftKRuntimeName("kk_long_highestOneBit")
external fun __longHighestOneBit(value: Long): Long

@KSwiftKRuntimeName("kk_long_lowestOneBit")
external fun __longLowestOneBit(value: Long): Long

@KSwiftKRuntimeName("kk_long_rotateLeft")
external fun __longRotateLeft(value: Long, distance: Int): Long

@KSwiftKRuntimeName("kk_long_rotateRight")
external fun __longRotateRight(value: Long, distance: Int): Long

@KSwiftKRuntimeName("kk_double_isNaN")
external fun __doubleIsNaN(value: Double): Boolean

@KSwiftKRuntimeName("kk_double_isInfinite")
external fun __doubleIsInfinite(value: Double): Boolean

@KSwiftKRuntimeName("kk_float_isNaN")
external fun __floatIsNaN(value: Float): Boolean

@KSwiftKRuntimeName("kk_float_isInfinite")
external fun __floatIsInfinite(value: Float): Boolean

@KSwiftKRuntimeName("kk_double_toBits")
external fun __doubleToBits(value: Double): Long

@KSwiftKRuntimeName("kk_double_toRawBits")
external fun __doubleToRawBits(value: Double): Long

@KSwiftKRuntimeName("kk_float_toBits")
external fun __floatToBits(value: Float): Int

@KSwiftKRuntimeName("kk_float_toRawBits")
external fun __floatToRawBits(value: Float): Int

@KSwiftKRuntimeName("kk_double_fromBits")
external fun __doubleFromBits(bits: Long): Double

@KSwiftKRuntimeName("kk_float_fromBits")
external fun __floatFromBits(bits: Int): Float

@KSwiftKRuntimeName("kk_require_lazy")
external fun __requireLazy(condition: Boolean, lazyMessage: () -> Any)

@KSwiftKRuntimeName("kk_check_lazy")
external fun __checkLazy(condition: Boolean, lazyMessage: () -> Any)

@KSwiftKRuntimeName("kk_precondition_assert")
external fun __assert(value: Boolean)

@KSwiftKRuntimeName("kk_precondition_assert_lazy")
external fun __assertLazy(value: Boolean, lazyMessage: () -> Any)

@KSwiftKRuntimeName("kk_todo_noarg")
external fun __todo(): Nothing

@KSwiftKRuntimeName("kk_todo")
external fun __todo(reason: String): Nothing

@KSwiftKRuntimeName("kk_println_newline")
external fun __println()

@KSwiftKRuntimeName("kk_println_any")
external fun __println(message: Any?)

@KSwiftKRuntimeName("kk_print_noarg")
external fun __print()

@KSwiftKRuntimeName("kk_print_any")
external fun __print(message: Any?)

@KSwiftKRuntimeName("kk_readlnOrNull")
external fun __readlnOrNull(): String?

@KSwiftKRuntimeName("kk_sys_write")
external fun __sys_write(fd: Int, buffer: ByteArray, count: Int): Int

@KSwiftKRuntimeName("kk_sys_read")
external fun __sys_read(fd: Int, buffer: ByteArray, count: Int): Int

@KSwiftKRuntimeName("kk_string_toByteArray")
external fun __string_toByteArray(strRaw: Int): Int

@KSwiftKRuntimeName("kk_string_from_utf8")
external fun __string_from_utf8(ptr: Int, len: Int): Int

@KSwiftKRuntimeName("kk_readln_from_syscall")
external fun __readln_from_syscall(outThrown: Int): String?

@KSwiftKRuntimeName("kk_synchronized")
external fun __synchronized(lock: Any, block: () -> Any?): Any

@KSwiftKRuntimeName("kk_system_exitProcess")
external fun __exitProcess(status: Int): Nothing

@KSwiftKRuntimeName("kk_system_getTimeMicros")
external fun __getTimeMicros(): Long

@KSwiftKRuntimeName("kk_system_getTimeMillis")
external fun __getTimeMillis(): Long

@KSwiftKRuntimeName("kk_system_getTimeNanos")
external fun __getTimeNanos(): Long

@KSwiftKRuntimeName("kk_math_sqrt")
external fun __mathSqrt(value: Double): Double

@KSwiftKRuntimeName("kk_math_sqrt_float")
external fun __mathSqrt(value: Float): Float

@KSwiftKRuntimeName("kk_math_ceil")
external fun __mathCeil(value: Double): Double

@KSwiftKRuntimeName("kk_math_ceil_float")
external fun __mathCeil(value: Float): Float

@KSwiftKRuntimeName("kk_math_floor")
external fun __mathFloor(value: Double): Double

@KSwiftKRuntimeName("kk_math_floor_float")
external fun __mathFloor(value: Float): Float

@KSwiftKRuntimeName("kk_math_round")
external fun __mathRound(value: Double): Double

@KSwiftKRuntimeName("kk_math_round_float")
external fun __mathRound(value: Float): Float

@KSwiftKRuntimeName("kk_math_truncate")
external fun __mathTruncate(value: Double): Double

@KSwiftKRuntimeName("kk_math_truncate_float")
external fun __mathTruncate(value: Float): Float

@KSwiftKRuntimeName("kk_math_sin")
external fun __mathSin(value: Double): Double

@KSwiftKRuntimeName("kk_math_sin_float")
external fun __mathSin(value: Float): Float

@KSwiftKRuntimeName("kk_math_cos")
external fun __mathCos(value: Double): Double

@KSwiftKRuntimeName("kk_math_cos_float")
external fun __mathCos(value: Float): Float

@KSwiftKRuntimeName("kk_math_tan")
external fun __mathTan(value: Double): Double

@KSwiftKRuntimeName("kk_math_tan_float")
external fun __mathTan(value: Float): Float

@KSwiftKRuntimeName("kk_math_asin")
external fun __mathAsin(value: Double): Double

@KSwiftKRuntimeName("kk_math_asin_float")
external fun __mathAsin(value: Float): Float

@KSwiftKRuntimeName("kk_math_acos")
external fun __mathAcos(value: Double): Double

@KSwiftKRuntimeName("kk_math_acos_float")
external fun __mathAcos(value: Float): Float

@KSwiftKRuntimeName("kk_math_atan")
external fun __mathAtan(value: Double): Double

@KSwiftKRuntimeName("kk_math_atan_float")
external fun __mathAtan(value: Float): Float

@KSwiftKRuntimeName("kk_math_atan2")
external fun __mathAtan2(y: Double, x: Double): Double

@KSwiftKRuntimeName("kk_math_atan2_float")
external fun __mathAtan2(y: Float, x: Float): Float

@KSwiftKRuntimeName("kk_math_exp")
external fun __mathExp(value: Double): Double

@KSwiftKRuntimeName("kk_math_exp_float")
external fun __mathExp(value: Float): Float

@KSwiftKRuntimeName("kk_math_expm1")
external fun __mathExpm1(value: Double): Double

@KSwiftKRuntimeName("kk_math_expm1_float")
external fun __mathExpm1(value: Float): Float

@KSwiftKRuntimeName("kk_math_ln")
external fun __mathLn(value: Double): Double

@KSwiftKRuntimeName("kk_math_ln_float")
external fun __mathLn(value: Float): Float

@KSwiftKRuntimeName("kk_math_ln1p")
external fun __mathLn1p(value: Double): Double

@KSwiftKRuntimeName("kk_math_ln1p_float")
external fun __mathLn1p(value: Float): Float

@KSwiftKRuntimeName("kk_math_log2")
external fun __mathLog2(value: Double): Double

@KSwiftKRuntimeName("kk_math_log2_float")
external fun __mathLog2(value: Float): Float

@KSwiftKRuntimeName("kk_math_log10")
external fun __mathLog10(value: Double): Double

@KSwiftKRuntimeName("kk_math_log10_float")
external fun __mathLog10(value: Float): Float

@KSwiftKRuntimeName("kk_math_sinh")
external fun __mathSinh(value: Double): Double

@KSwiftKRuntimeName("kk_math_sinh_float")
external fun __mathSinh(value: Float): Float

@KSwiftKRuntimeName("kk_math_cosh")
external fun __mathCosh(value: Double): Double

@KSwiftKRuntimeName("kk_math_cosh_float")
external fun __mathCosh(value: Float): Float

@KSwiftKRuntimeName("kk_math_tanh")
external fun __mathTanh(value: Double): Double

@KSwiftKRuntimeName("kk_math_tanh_float")
external fun __mathTanh(value: Float): Float

@KSwiftKRuntimeName("kk_math_cbrt")
external fun __mathCbrt(value: Double): Double

@KSwiftKRuntimeName("kk_math_cbrt_float")
external fun __mathCbrt(value: Float): Float

@KSwiftKRuntimeName("kk_math_acosh")
external fun __mathAcosh(value: Double): Double

@KSwiftKRuntimeName("kk_math_acosh_float")
external fun __mathAcosh(value: Float): Float

@KSwiftKRuntimeName("kk_math_asinh")
external fun __mathAsinh(value: Double): Double

@KSwiftKRuntimeName("kk_math_asinh_float")
external fun __mathAsinh(value: Float): Float

@KSwiftKRuntimeName("kk_math_atanh")
external fun __mathAtanh(value: Double): Double

@KSwiftKRuntimeName("kk_math_atanh_float")
external fun __mathAtanh(value: Float): Float

@KSwiftKRuntimeName("kk_math_hypot")
external fun __mathHypot(x: Double, y: Double): Double

@KSwiftKRuntimeName("kk_math_hypot_float")
external fun __mathHypot(x: Float, y: Float): Float

@KSwiftKRuntimeName("kk_double_ulp")
external fun __doubleUlp(value: Double): Double

@KSwiftKRuntimeName("kk_float_ulp")
external fun __floatUlp(value: Float): Float

@KSwiftKRuntimeName("kk_double_nextUp")
external fun __doubleNextUp(value: Double): Double

@KSwiftKRuntimeName("kk_float_nextUp")
external fun __floatNextUp(value: Float): Float

@KSwiftKRuntimeName("kk_double_nextDown")
external fun __doubleNextDown(value: Double): Double

@KSwiftKRuntimeName("kk_float_nextDown")
external fun __floatNextDown(value: Float): Float

@KSwiftKRuntimeName("kk_double_roundToInt")
external fun __doubleRoundToInt(value: Double): Int

@KSwiftKRuntimeName("kk_float_roundToInt")
external fun __floatRoundToInt(value: Float): Int

@KSwiftKRuntimeName("kk_double_roundToLong")
external fun __doubleRoundToLong(value: Double): Long

@KSwiftKRuntimeName("kk_float_roundToLong")
external fun __floatRoundToLong(value: Float): Long

@KSwiftKRuntimeName("kk_math_pow")
external fun __mathPow(value: Double, exponent: Double): Double

@KSwiftKRuntimeName("kk_math_pow_float")
external fun __mathPow(value: Float, exponent: Float): Float

@KSwiftKRuntimeName("kk_math_max")
external fun __mathMax(a: Double, b: Double): Double

@KSwiftKRuntimeName("kk_math_max_float")
external fun __mathMax(a: Float, b: Float): Float

@KSwiftKRuntimeName("kk_math_min")
external fun __mathMin(a: Double, b: Double): Double

@KSwiftKRuntimeName("kk_math_min_float")
external fun __mathMin(a: Float, b: Float): Float

@KSwiftKRuntimeName("kk_test_assertEquals")
external fun __testAssertEquals(expected: Any?, actualValue: Any?)

@KSwiftKRuntimeName("kk_test_assertEquals_message")
external fun __testAssertEqualsMessage(expected: Any?, actualValue: Any?, message: Any?)

@KSwiftKRuntimeName("kk_test_assertTrue")
external fun __testAssertTrue(actualValue: Boolean)

@KSwiftKRuntimeName("kk_test_assertTrue_message")
external fun __testAssertTrueMessage(actualValue: Boolean, message: Any?)

@KSwiftKRuntimeName("kk_test_assertNull")
external fun __testAssertNull(actualValue: Any?)

@KSwiftKRuntimeName("kk_test_assertNull_message")
external fun __testAssertNullMessage(actualValue: Any?, message: Any?)
