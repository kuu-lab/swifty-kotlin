// KUU-4321: Throwable.initCause JVM guards — self-cause → IllegalArgumentException,
// overwrite of an initialized cause → IllegalStateException (ctor-provided and
// initCause(null) both count as initialized).

class MyException(msg: String) : Exception(msg)
class MyCauseEx(msg: String, c: Throwable?) : Exception(msg, c)

fun main() {
    // 1. Self-causation on a fresh throwable → IllegalArgumentException, and
    //    the thrown exception carries the receiver as its cause (JDK parity).
    val selfTarget = Exception("self")
    try {
        selfTarget.initCause(selfTarget)
        println("self: no throw")
    } catch (ex: IllegalArgumentException) {
        println("self: ${ex::class.simpleName} '${ex.message}' causeIsReceiver=${ex.cause === selfTarget}")
    }

    // 2. First initCause succeeds and returns the receiver.
    val first = RuntimeException("first-target")
    val holder = Exception("holder")
    val returned = holder.initCause(first)
    println("first: returned===holder ${returned === holder}, cause===first ${holder.cause === first}")

    // 3. Second initCause → IllegalStateException "Can't overwrite cause with <arg>".
    try {
        holder.initCause(IllegalStateException("second"))
        println("double: no throw")
    } catch (ex: IllegalStateException) {
        println("double: ${ex::class.simpleName} '${ex.message}'")
    }

    // 4. initCause(null) succeeds once, then counts as initialized.
    val nul = Exception("nul")
    val nulReturned = nul.initCause(null)
    println("nullOnce: returned===nul ${nulReturned === nul}, cause=${nul.cause}")
    try {
        nul.initCause(RuntimeException("after-null"))
        println("nullTwice: no throw")
    } catch (ex: IllegalStateException) {
        println("nullTwice: ${ex::class.simpleName} '${ex.message}'")
    }

    // 5. Constructor-provided cause (non-null) → initCause fails.
    val ctorCauseTarget = Exception("m", RuntimeException("ctor-cause"))
    try {
        ctorCauseTarget.initCause(IllegalStateException("x"))
        println("ctorCause: no throw")
    } catch (ex: IllegalStateException) {
        println("ctorCause: ${ex::class.simpleName} '${ex.message}'")
    }

    // 6. Constructor-provided null cause still counts as initialized.
    val ctorNullTarget = Exception("m", null)
    try {
        ctorNullTarget.initCause(IllegalStateException("x"))
        println("ctorNullCause: no throw")
    } catch (ex: IllegalStateException) {
        println("ctorNullCause: ${ex::class.simpleName} '${ex.message}'")
    }

    // 7. Throwable(cause) constructor → initCause fails.
    val throwableCauseTarget = Throwable(RuntimeException("only-cause"))
    try {
        throwableCauseTarget.initCause(IllegalStateException("x"))
        println("throwableCauseCtor: no throw")
    } catch (ex: IllegalStateException) {
        println("throwableCauseCtor: ${ex::class.simpleName} '${ex.message}'")
    }

    // 8. Message-only constructors leave the cause uninitialized.
    val msgOnly = Exception("msg-only")
    msgOnly.initCause(RuntimeException("late"))
    println("msgOnly: cause=${msgOnly.cause?.message}")
    val bare = Throwable()
    bare.initCause(RuntimeException("bare-late"))
    println("bare: cause=${bare.cause?.message}")

    // 9. Kotlin-defined subclass: self-cause and double initCause.
    val subSelf = MyException("self")
    try {
        subSelf.initCause(subSelf)
        println("subSelf: no throw")
    } catch (ex: IllegalArgumentException) {
        println("subSelf: ${ex::class.simpleName} '${ex.message}' causeIsReceiver=${ex.cause === subSelf}")
    }
    val subDouble = MyException("two")
    try {
        subDouble.initCause(IllegalStateException("first"))
        subDouble.initCause(RuntimeException("second"))
        println("subDouble: no throw")
    } catch (ex: IllegalStateException) {
        println("subDouble: ${ex::class.simpleName} '${ex.message}'")
    }
    // Subclass with cause-taking super ctor stays initialized.
    val subCtorCause = MyCauseEx("mc", RuntimeException("c"))
    try {
        subCtorCause.initCause(IllegalStateException("x"))
        println("subCtorCause: no throw")
    } catch (ex: IllegalStateException) {
        println("subCtorCause: ${ex::class.simpleName} '${ex.message}'")
    }
    // Subclass with message-only super ctor stays uninitialized.
    val subMsgOnly = MyException("msg-only-sub")
    subMsgOnly.initCause(RuntimeException("sub-late"))
    println("subMsgOnly: cause=${subMsgOnly.cause?.message}")

    // 10. initCause(this) on an already-initialized throwable → overwrite wins.
    val initSelf = Exception("init-self")
    try {
        initSelf.initCause(RuntimeException("first"))
        initSelf.initCause(initSelf)
        println("initSelfAfterInit: no throw")
    } catch (ex: IllegalStateException) {
        println("initSelfAfterInit: ${ex::class.simpleName} '${ex.message}'")
    }

    // 11. The thrown guard exceptions carry the receiver as their cause (JDK parity).
    val guardIae = Exception("guard-cause")
    try {
        guardIae.initCause(guardIae)
    } catch (ex: IllegalArgumentException) {
        println("guardCauseIae: causeIsReceiver=${ex.cause === guardIae}")
    }
    val guardIse = Exception("guard-cause2")
    try {
        guardIse.initCause(RuntimeException("c"))
        guardIse.initCause(RuntimeException("d"))
    } catch (ex: IllegalStateException) {
        println("guardCauseIse: causeIsReceiver=${ex.cause === guardIse}")
    }

    // 12. addSuppressed(self) is silently ignored (Kotlin/JVM @HidesMembers semantics).
    val sup = Exception("sup")
    sup.addSuppressed(sup)
    println("addSuppressedSelf: size=${sup.suppressed.size}")
}
