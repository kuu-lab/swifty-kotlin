package kotlin
open class Throwable { constructor(); constructor(message: String?); constructor(message: String?, cause: Throwable?); constructor(cause: Throwable?); val message: String? get() = null }
open class Error: Throwable { constructor(): super(); constructor(message: String?): super(message); constructor(message: String?, cause: Throwable?): super(message, cause); constructor(cause: Throwable?): super(cause) }
open class NegativeArraySizeException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class UnsupportedOperationException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class Exception: Throwable { constructor(): super(); constructor(message: String?): super(message); constructor(message: String?, cause: Throwable?): super(message, cause); constructor(cause: Throwable?): super(cause) }
open class RuntimeException: Exception { constructor(): super(); constructor(message: String?): super(message); constructor(message: String?, cause: Throwable?): super(message, cause); constructor(cause: Throwable?): super(cause) }
open class IllegalArgumentException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class IllegalStateException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class IndexOutOfBoundsException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class ArrayIndexOutOfBoundsException: IndexOutOfBoundsException { constructor(): super(); constructor(message: String?): super(message) }
open class ArithmeticException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class NumberFormatException: IllegalArgumentException { constructor(): super(); constructor(message: String?): super(message) }
open class NullPointerException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
open class ClassCastException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
