package kotlin
open class Throwable {
    constructor()
    constructor(message: String?)
    constructor(message: String?, cause: Throwable?)
    constructor(cause: Throwable?)

    val message: String? get() = null
    val cause: Throwable? get() = null
    val stackTrace: Array<java.lang.StackTraceElement> get() = null!!
    val suppressed: Array<Throwable> get() = null!!

    fun initCause(cause: Throwable?): Throwable = this
    fun addSuppressed(exception: Throwable) {}
    fun printStackTrace() {}
    fun fillInStackTrace(): Throwable = this
}
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
