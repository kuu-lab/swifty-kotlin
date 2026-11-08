#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4101: an inferred member property declared in a later declaration
/// (`val size get() = data.size` on a class, `val isZero get() = signum == 0`
/// on an interface) must publish its type before earlier bodies read it —
/// otherwise `x.size` sees the `Any?` placeholder, downstream expressions
/// degrade to the error type, and the member read falls back to a same-named
/// bundled function, reporting `KSWIFTK-SEMA-0309` ("function invocation
/// expected") on a plain property access (kbignum's `CommonBigInt`).
@Suite
struct InferredMemberPropertyForwardReferenceTests {
    @Test
    func laterClassGetterPropertyReadsFromEarlierBody() throws {
        // `P3.size` derives from the intrinsic array member `IntArray.size`,
        // which member lookup cannot see — the precheck must fall back to the
        // statically known result type.
        let ctx = makeContextFromSource("""
        class C3 private constructor(val data: P3, override val signum: Int, var dummy: Boolean) : Iface, Ctor3 by C3 {
            companion object : Ctor3 {
                operator fun invoke(data: P3, signum: Int): C3 = C3(data, signum, false)
                override fun create(v: Int): C3 = C3(P3(1), 1, false)
            }
            override fun inv(): C3 {
                val out = P3(this.data.size)
                val s = out.size
                return C3(out, s, false)
            }
        }

        class P3 internal constructor(val data: IntArray) {
            val size get() = data.size
            constructor(size: Int) : this(IntArray(if (size > 1) size else 1))
        }

        interface Iface { val signum: Int; fun inv(): Iface }
        interface Ctor3 { fun create(v: Int): Iface }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func laterClassGetterPropertyInsideAlsoLambda() throws {
        // The reported shape: `P3(this.data.size).also { ... it.size ... }`
        // on an error receiver used to bind the bundled `size()` function.
        let ctx = makeContextFromSource("""
        class C3(val data: P3) {
            fun inv(): C3 = C3(
                P3(this.data.size).also {
                    for (n in 0 until it.size) it[n] = this.data[n]
                }
            )
        }

        class P3 internal constructor(val data: IntArray) {
            val size get() = data.size
            constructor(size: Int) : this(IntArray(if (size > 1) size else 1))
            operator fun get(index: Int): Int = data[index]
            operator fun set(index: Int, value: Int) { data[index] = value }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func interfaceGetterPropertyReadsFromEarlierBody() throws {
        // Interfaces went through no member-property precheck at all, so an
        // inferred interface getter stayed `Any?` for every forward read.
        let ctx = makeContextFromSource("""
        class C3(val data: P3) {
            fun inv(): Boolean = if (data.isZero) data.isNegative else !data.isPositive
        }

        class P3(override val signum: Int) : Iface

        interface Iface {
            val signum: Int
            val isZero get() = signum == 0
            val isNegative get() = signum < 0
            val isPositive get() = signum > 0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func overloadedCallInitializerGetterPropertyReadsFromEarlierBody() throws {
        // KUU-4270: `cleanedAndPointers` has no declared type, and its
        // initializer `atomicBox(0)` is applicable to two overloads with
        // different result types (`atomicBox(Int)` vs `atomicBox<T>(T)`).
        // The precheck must still publish `AtomicIntBox` — the
        // declared-shape-over-bare-type-parameter winner — so the inferred
        // `isRemoved` getter resolves to `Boolean` for the earlier
        // `findIt` body instead of degrading to a condition-type error.
        let ctx = makeContextFromSource("""
        class AtomicIntBox { val value: Int = 0 }
        class AtomicRefBox<T>(val v: T)
        fun atomicBox(i: Int): AtomicIntBox = AtomicIntBox()
        fun <T> atomicBox(t: T): AtomicRefBox<T> = AtomicRefBox(t)

        internal fun <S : Segment2<S>> S.findIt(id: Long): S {
            var cur: S = this
            while (cur.isRemoved) {
                cur = cur
            }
            return cur
        }

        internal abstract class Node2<N : Node2<N>>(prev: N?) {
            abstract val isRemoved: Boolean
        }

        internal abstract class Segment2<S : Segment2<S>>(prev: S?, pointers: Int) : Node2<S>(prev) {
            abstract val numberOfSlots: Int
            private val cleanedAndPointers = atomicBox(0)
            override val isRemoved get() = cleanedAndPointers.value == numberOfSlots
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitTypeArgumentConstructorWithDeferredArgumentPublishesType() throws {
        // KUU-4280 (kotlinx.collections.immutable TrieNode): a companion
        // singleton `EMPTY = TrieNode<Nothing>(0, emptyArray())` pins its
        // result through explicit type arguments even though `emptyArray()`
        // cannot be typed during the early pass. The earlier-file reader must
        // still see `TrieNode<Nothing>` — and `TrieNode` in expression
        // position must resolve to its companion object — so
        // `TrieNode.EMPTY.buffer` publishes `Array<Any?>` instead of `Any?`.
        let consumer = """
        package consumer
        import lib.*
        class Reader {
            val bufferSize: Int = TrieNode.EMPTY.buffer.size
        }
        """
        let lib = """
        package lib
        class TrieNode<E>(val dataMap: Int, val buffer: Array<Any?>) {
            companion object {
                val EMPTY = TrieNode<Nothing>(0, emptyArray())
            }
        }
        """
        for sources in [[consumer, lib], [lib, consumer]] {
            let ctx = makeContextFromSources(sources)
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected TrieNode.EMPTY to publish its pinned type, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func aliasedDefaultImportConstructorPublishesType() throws {
        // KUU-4502: `IllegalStateException` binds both the `kotlin` class and
        // the `java.lang` typealias that aliases it (both default imports),
        // so the raw scope lookup yields two candidates for one nominal. The
        // precheck must still publish the getter's type — otherwise the
        // earlier `throw sendException` sees the `Any?` placeholder.
        let ctx = makeContextFromSource("""
        class Derived : Base() {
            fun send() {
                if (true) throw sendException
            }
        }

        open class Base {
            protected val sendException get() = IllegalStateException("closed")
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unresolvedGetterBodyStaysOnNormalPass() throws {
        // The intrinsic array fallback must not invent a type for a body that
        // genuinely does not resolve — `size` here has no receiver and no
        // declaration, so the authoritative pass still reports the error.
        let ctx = makeContextFromSource("""
        class A { val x get() = size }
        class B { val size: Int = 7 }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func castGetterPropertyPublishesTypeForInheritedArgument() throws {
        // KUU-4193 (kotlinx.coroutines BroadcastChannel): `closeCause` is a
        // protected getter-only property whose body is an `as` cast over an
        // `Any?` atomic read, declared in `BufferedChannel` while the
        // `s.close(closeCause)` call site lives in the earlier-checked
        // `BroadcastChannelImpl`. The cast result type comes from the target
        // alone, so the precheck must publish `Throwable?` before that body
        // observes the `Any?` header placeholder — getter-only properties
        // cannot resolve on demand, so the placeholder otherwise survives
        // into overload resolution and the call is rejected with
        // KSWIFTK-SEMA-0473.
        let ctx = makeContextFromSource("""
        interface SendChannel<E> {
            fun close(cause: Throwable? = null): Boolean
        }

        class BroadcastChannelImpl<E> : BufferedChannel<E>() {
            fun openSubscription(): BufferedChannel<E> {
                val s = SubscriberBuffered<E>()
                if (closeCause != null) {
                    s.close(closeCause)
                    return s
                }
                return s
            }
        }

        class SubscriberBuffered<E> : BufferedChannel<E>()

        open class BufferedChannel<E> : SendChannel<E> {
            private val box: Any? = null
            protected val closeCause get() = box as Throwable?
            override fun close(cause: Throwable?): Boolean = cause != null
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func safeCastGetterPropertyPublishesNullableType() throws {
        // The `as?` variant must publish the nullable target type so a
        // nullable parameter accepts the argument.
        let ctx = makeContextFromSource("""
        class Derived : Base() {
            fun openSub(): Boolean = close(cause)
        }

        open class Base {
            private val box: Any? = null
            protected val cause get() = box as? Throwable
            fun close(c: Throwable?): Boolean = true
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func castGetterPropertyPublishesRealTypeNotWildcard() throws {
        // Publishing must surface the cast target itself: an `Int` getter
        // argument still mismatches a `Throwable?` parameter.
        let ctx = makeContextFromSource("""
        class Derived : Base() {
            fun openSub(): Boolean = close(cause)
        }

        open class Base {
            private val box: Any? = null
            protected val cause get() = box as Int
            fun close(c: Throwable?): Boolean = true
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func elvisGetterPropertyPublishesTypeForInheritedThrow() throws {
        // KUU-4194 (kotlinx.coroutines BufferedChannel): `sendException` is a
        // getter-only property `closeCause ?: ClosedSendChannelException(...)`
        // declared in the later-checked `BufferedChannel` base class, while
        // `BroadcastChannelImpl.send` throws it from the earlier-checked
        // file. The elvis probe must join the non-null lhs with the rhs so
        // the published type is `Throwable`, not the `Any?` header
        // placeholder — `throw sendException` otherwise reports
        // KSWIFTK-SEMA-0414.
        let ctx = makeContextFromSource("""
        class Derived : Base() {
            fun send() {
                if (true) throw sendException
            }
        }

        open class Base {
            private var cause: Any? = null
            protected val closeCause get() = cause as Throwable?
            protected val sendException get() = closeCause ?: SendClosed()
        }

        class SendClosed : Exception("closed")
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func elvisGetterPropertyPublishesJoinedTypeNotWildcard() throws {
        // The published type is the lhs/rhs join: reading the getter where a
        // `String` is required must still fail, and reading it as `Throwable`
        // must succeed — together they pin the published type to `Throwable`.
        let okCtx = makeContextFromSource("""
        class Derived : Base() {
            fun readIt(): Throwable = sendException
        }

        open class Base {
            private var cause: Any? = null
            protected val closeCause get() = cause as Throwable?
            protected val sendException get() = closeCause ?: SendClosed()
        }

        class SendClosed : Exception("closed")
        """)
        try runSema(okCtx)
        #expect(!okCtx.diagnostics.hasError, "\(okCtx.diagnostics.diagnostics)")

        let badCtx = makeContextFromSource("""
        class Derived : Base() {
            fun readIt(): String = sendException
        }

        open class Base {
            private var cause: Any? = null
            protected val closeCause get() = cause as Throwable?
            protected val sendException get() = closeCause ?: SendClosed()
        }

        class SendClosed : Exception("closed")
        """)
        try runSema(badCtx)
        #expect(badCtx.diagnostics.hasError)
    }

    @Test
    func elvisThrowOnInheritedGetterPropertyUsesPublishedType() throws {
        // KUU-4197 (kotlinx.coroutines ConflatedBroadcastChannel.cancelImpl):
        // `throw closeCause ?: IllegalStateException(...)` reads the
        // forward-published `closeCause: Throwable?` from the later-checked
        // base class; the authoritative elvis join must yield `Throwable`
        // for `throw` to accept it instead of degrading to `Any`.
        let ctx = makeContextFromSource("""
        class Derived : Base() {
            fun cancel() {
                throw closeCause ?: IllegalStateException("closed")
            }
        }

        open class Base {
            private var cause: Any? = null
            protected val closeCause get() = cause as Throwable?
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
