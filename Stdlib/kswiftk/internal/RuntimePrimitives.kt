package kswiftk.internal

// MARK: - System calls

@KSwiftKRuntimeName("kk_sys_write")
external fun __sys_write(fd: Int, buffer: ByteArray, count: Int): Int

@KSwiftKRuntimeName("kk_readln_from_syscall")
external fun __readln_from_syscall(outThrown: Int): String?

@KSwiftKRuntimeName("kk_system_exitProcess")
external fun __exitProcess(status: Int): Nothing

// MARK: - Time functions (system-level APIs)

@KSwiftKRuntimeName("kk_system_getTimeMicros")
external fun __getTimeMicros(): Long

@KSwiftKRuntimeName("kk_system_getTimeMillis")
external fun __getTimeMillis(): Long

@KSwiftKRuntimeName("kk_system_getTimeNanos")
external fun __getTimeNanos(): Long

// MARK: - Synchronization (necessary for thread safety)

@KSwiftKRuntimeName("kk_synchronized")
external fun __synchronized(lock: Any, block: () -> Any?): Any

// MARK: - Floating point bit operations (low-level bit manipulation)

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

// MARK: - Char functions (Unicode-dependent, require runtime)

@KSwiftKRuntimeName("kk_char_isDigit")
external fun __char_isDigit(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLetter")
external fun __char_isLetter(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLetterOrDigit")
external fun __char_isLetterOrDigit(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isUpperCase")
external fun __char_isUpperCase(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLowerCase")
external fun __char_isLowerCase(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isWhitespace")
external fun __char_isWhitespace(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isDefined")
external fun __char_isDefined(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isSurrogate")
external fun __char_isSurrogate(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isHighSurrogate")
external fun __char_isHighSurrogate(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLowSurrogate")
external fun __char_isLowSurrogate(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isISOControl")
external fun __char_isISOControl(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isTitleCase")
external fun __char_isTitleCase(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isJavaIdentifierPart")
external fun __char_isJavaIdentifierPart(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isIdentifierIgnorable")
external fun __char_isIdentifierIgnorable(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isUnicodeIdentifierPart")
external fun __char_isUnicodeIdentifierPart(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isJavaIdentifierStart")
external fun __char_isJavaIdentifierStart(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_uppercaseChar")
external fun __char_uppercaseChar(c: Char): Char

@KSwiftKRuntimeName("kk_char_lowercaseChar")
external fun __char_lowercaseChar(c: Char): Char

@KSwiftKRuntimeName("kk_char_titlecaseChar")
external fun __char_titlecaseChar(c: Char): Char

@KSwiftKRuntimeName("kk_char_uppercase")
external fun __char_uppercase(c: Char): Char

@KSwiftKRuntimeName("kk_char_lowercase")
external fun __char_lowercase(c: Char): Char

@KSwiftKRuntimeName("kk_char_titlecase")
external fun __char_titlecase(c: Char): Char

@KSwiftKRuntimeName("kk_char_digitToInt")
external fun __char_digitToInt(c: Char): Int

@KSwiftKRuntimeName("kk_char_digitToIntOrNull")
external fun __char_digitToIntOrNull(c: Char): Int?

@KSwiftKRuntimeName("kk_char_digitToInt_radix")
external fun __char_digitToInt_radix(c: Char, radix: Int): Int

// MARK: - String struct field access functions (new struct-based representation)

@KSwiftKRuntimeName("kk_string_struct_get_length")
external fun __string_struct_get_length(s: String): Int

// MARK: - String operations still requiring runtime support

@KSwiftKRuntimeName("kk_string_compareTo_flat")
external fun __string_compareTo_flat(s1: String, s2: String): Int

@KSwiftKRuntimeName("kk_string_concat")
external fun __string_concat(s1: String, s2: String): String

@KSwiftKRuntimeName("kk_string_get_flat")
external fun __string_get_flat(s: String, index: Int): Char
