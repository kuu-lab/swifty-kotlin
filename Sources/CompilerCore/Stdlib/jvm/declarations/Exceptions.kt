package kotlin
open class Throwable { constructor(); constructor(message: String?); val message: String? get() = null }
open class NegativeArraySizeException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class UnsupportedOperationException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class Exception: Throwable { constructor(): super(); constructor(message: String?): super(message) }
open class RuntimeException: Exception { constructor(): super(); constructor(message: String?): super(message) }
open class IllegalArgumentException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class IllegalStateException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class IndexOutOfBoundsException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class ArrayIndexOutOfBoundsException: IndexOutOfBoundsException { constructor(): super(); constructor(message: String?): super(message) }
open class ArithmeticException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class NumberFormatException: IllegalArgumentException { constructor(): super(); constructor(message: String?): super(message) }
open class NullPointerException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class ClassCastException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
