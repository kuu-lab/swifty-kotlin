@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

// STDLIB-033: kotlin.concurrent / kotlin.concurrent.atomics parity edge cases
@Suite
struct CodegenBackendAtomicExtendedEdgeCasesTests {

    @Test
    func testCodegenAtomicNativePtrConstructorLinksAndStoresInitialValue() throws {
        let source = """
        @file:OptIn(
            kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
            kotlinx.cinterop.ExperimentalForeignApi::class
        )
        import kotlin.concurrent.atomics.AtomicNativePtr
        import kotlin.internal.KsSymbolName
        import kotlinx.cinterop.COpaquePointer
        import kotlinx.cinterop.NativePtr
        import kotlinx.cinterop.StableRef

        @KsSymbolName("kk_copaque_pointer_address")
        private external fun pointerAddress(pointer: COpaquePointer?): NativePtr

        fun main() {
            val first = pointerAddress(null)
            val reference = StableRef.create("second")
            val second = pointerAddress(reference.asCPointer())
            val atomic = AtomicNativePtr(first)
            println(atomic.value == first)
            atomic.value = second
            println(atomic.value == second)
            println(atomic.value != first)
            reference.dispose()
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicNativePtrConstructorLink", expected: "true\ntrue\ntrue\n")
    }

    @Test
    func testCodegenAtomicIntCASSuccessReturnsTrueAndUpdatesValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(10)
            val result = a.compareAndSet(10, 20)
            println(result)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntCASSuccess", expected: "true\n20\n")
    }

    @Test
    func testCodegenJavaAtomicIntegerDirectConstruction() throws {
        let source = """
        import java.util.concurrent.atomic.AtomicInteger

        fun main() {
            val counter = AtomicInteger(0)
            counter.incrementAndGet()
            counter.incrementAndGet()
            counter.addAndGet(3)
            println(counter.get())
        }
        """
        try assertKotlinOutput(source, moduleName: "JavaAtomicIntegerDirectConstruction", expected: "5\n")
    }

    @Test
    func testCodegenAtomicIntCASFailureReturnsFalseAndLeavesValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(10)
            val result = a.compareAndSet(99, 20)
            println(result)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntCASFailure", expected: "false\n10\n")
    }

    @Test
    func testCodegenAtomicIntCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(5)
            // Success: returns old value (5), updates to 10
            println(a.compareAndExchange(5, 10))
            println(a.load())
            // Failure: returns current value (10), leaves unchanged
            println(a.compareAndExchange(99, 20))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntCAE", expected: "5\n10\n10\n10\n")
    }

    @Test
    func testCodegenAtomicIntFetchAndIncrementReturnsOldValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(7)
            println(a.fetchAndIncrement())
            println(a.load())
            println(a.fetchAndDecrement())
            println(a.load())
            println(a.incrementAndFetch())
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntIncrement", expected: "7\n8\n8\n7\n8\n8\n")
    }

    @Test
    func testCodegenAtomicIntInt32OverflowPreservesCASSemantics() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(Int.MAX_VALUE)
            println(a.incrementAndFetch())
            println(a.compareAndSet(Int.MIN_VALUE, 5))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntInt32Overflow", expected: "-2147483648\ntrue\n5\n")
    }

    @Test
    func testCodegenAtomicIntStoreAndLoad() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            println(a.load())
            a.store(42)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntStoreLoad", expected: "0\n42\n")
    }

    @Test
    func testCodegenAtomicLongBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(100L)
            println(a.load())
            a.store(200L)
            println(a.load())
            println(a.exchange(300L))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongBasic", expected: "100\n200\n200\n300\n")
    }

    @Test
    func testCodegenAtomicLongCASSuccessAndFailure() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(50L)
            println(a.compareAndSet(50L, 60L))
            println(a.load())
            println(a.compareAndSet(99L, 70L))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongCAS", expected: "true\n60\nfalse\n60\n")
    }

    @Test
    func testCodegenAtomicLongCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(10L)
            println(a.compareAndExchange(10L, 20L))
            println(a.load())
            println(a.compareAndExchange(999L, 30L))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongCAE", expected: "10\n20\n20\n20\n")
    }

    @Test
    func testCodegenAtomicLongArithmeticOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(1L)
            println(a.addAndFetch(4L))
            println(a.fetchAndAdd(3L))
            println(a.load())
            println(a.fetchAndIncrement())
            println(a.load())
            println(a.fetchAndDecrement())
            println(a.load())
            println(a.incrementAndFetch())
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArithmetic", expected: "5\n5\n8\n8\n9\n9\n8\n9\n9\n")
    }

    @Test
    func testCodegenAtomicLongNegativeDeltaArithmetic() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong

        fun main() {
            val a = AtomicLong(10L)
            println(a.addAndFetch(-3L))
            println(a.load())
            println(a.fetchAndAdd(-2L))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongNegativeDelta", expected: "7\n7\n7\n5\n")
    }

    @Test
    func testCodegenAtomicBooleanBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            println(a.load())
            a.store(true)
            println(a.load())
            println(a.exchange(false))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanBasic", expected: "false\ntrue\ntrue\nfalse\n")
    }

    @Test
    func testCodegenAtomicBooleanLoadStoreExchange() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            println(a.load())
            a.store(true)
            println(a.load())
            println(a.exchange(false))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanGetSet", expected: "false\ntrue\ntrue\nfalse\n")
    }

    @Test
    func testCodegenAtomicBooleanCASSuccessAndFailure() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(true)
            println(a.compareAndSet(false, false))
            println(a.load())
            println(a.compareAndSet(true, false))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanCAS", expected: "false\ntrue\ntrue\nfalse\n")
    }

    @Test
    func testCodegenAtomicBooleanCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            // Success: returns old (false), updates to true
            println(a.compareAndExchange(false, true))
            println(a.load())
            // Failure: returns current (true), unchanged
            println(a.compareAndExchange(false, false))
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBooleanCAE", expected: "false\ntrue\ntrue\ntrue\n")
    }

    @Test
    func testCodegenAtomicReferenceIdentityVsEqualityCAS() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        data class Token(val id: Int)

        fun main() {
            val current = Token(1)
            val equalButDistinct = Token(1)
            val replacement = Token(2)
            val ref = AtomicReference(current)
            // AtomicReference CAS compares references, not structural equality.
            println(ref.compareAndSet(equalButDistinct, replacement))
            println(ref.load() === current)
            println(ref.compareAndSet(current, replacement))
            println(ref.load() === replacement)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefIdentity", expected: "false\ntrue\ntrue\ntrue\n")
    }

    @Test
    func testCodegenAtomicReferenceCompareAndExchangeReturnsCurrentValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        data class Token(val value: String)

        fun main() {
            val a = Token("alpha")
            val b = Token("beta")
            val c = Token("gamma")
            val ref = AtomicReference(a)
            // Success: returns old value (a) and stores b.
            val old = ref.compareAndExchange(a, b)
            println(old === a)
            println(ref.load() === b)
            // Failure: returns current (b), unchanged.
            val cur = ref.compareAndExchange(c, a)
            println(cur === b)
            println(ref.load() === b)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefCAE", expected: "true\ntrue\ntrue\ntrue\n")
    }

    @Test
    func testCodegenAtomicReferenceStringCompareAndExchangeUsesLoadedReference() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val reference = AtomicReference("x")
            reference.store("y")
            val expected = reference.load()
            println(expected === reference.load())
            val old = reference.compareAndExchange(expected, "z")
            println(old === expected)
            println(reference.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefStringCAE", expected: "true\ntrue\nz\n")
    }

    @Test
    func testCodegenLegacyAtomicReferenceStringCompareAndExchangeUsesLoadedReference() throws {
        let source = """
        import kotlin.concurrent.AtomicReference

        fun main() {
            val reference = AtomicReference("x")
            reference.value = "y"
            val expected = reference.value
            println(expected === reference.value)
            val old = reference.compareAndExchange(expected, "z")
            println(old)
            println(reference.value)
        }
        """
        try assertKotlinOutput(source, moduleName: "LegacyAtomicRefStringCAE", expected: "true\ny\nz\n")
    }

    @Test
    func testCodegenAtomicReferenceExchangeAndStore() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val ref = AtomicReference("v1")
            // exchange returns old, stores new
            val prev = ref.exchange("v2")
            println(prev)
            println(ref.load())
            // store then load
            ref.store("v3")
            println(ref.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefExchangeStore", expected: "v1\nv2\nv3\n")
    }

    @Test
    func testCodegenAtomicArrayFetchAndUpdateAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = atomicArrayOfNulls<String>(1)
            arr.storeAt(0, "a")
            val old = arr.fetchAndUpdateAt(0) { (it ?: "") + "b" }
            println(old)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayFetchAndUpdateAt", expected: "a\nab\n")
    }

    @Test
    func testCodegenAtomicArrayUpdateAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = atomicArrayOfNulls<String>(1)
            arr.storeAt(0, "a")
            arr.updateAt(0) { (it ?: "") + "b" }
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayUpdateAt", expected: "ab\n")
    }

    @Test
    func testCodegenAtomicArrayCompareAndSetAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = atomicArrayOfNulls<String>(1)
            arr.storeAt(0, "a")
            val old = arr.loadAt(0)
            println(arr.compareAndSetAt(0, old, "b"))
            println(arr.loadAt(0))
            println(arr.compareAndSetAt(0, old, "c"))
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayCompareAndSetAt", expected: "true\nb\nfalse\nb\n")
    }

    @Test
    func testCodegenAtomicArrayOfNullsFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = atomicArrayOfNulls<String>(2)
            println(arr.size)
            arr.storeAt(0, "first")
            arr.storeAt(1, "value")
            println(arr.loadAt(0))
            println(arr.loadAt(1))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayOfNullsFactory", expected: "2\nfirst\nvalue\n")
    }

    @Test
    func testCodegenLegacyAtomicArrayConstructorsAndCopySemantics() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.concurrent.AtomicArray

        fun main() {
            val initialized = AtomicArray(2) { index -> index.toString() }
            val source = arrayOf("alpha", "beta")
            val copied = AtomicArray(source)
            source[0] = "x"
            println(initialized)
            println(copied)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LegacyAtomicArrayConstructors",
            expected: "[0, 1]\n[alpha, beta]\n"
        )
    }

    @Test
    func testCodegenAtomicArrayOfFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = AtomicArray(arrayOf("first", "value"))
            println(arr.size)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
            arr.storeAt(1, "next")
            println(arr.loadAt(1))

            val empty = atomicArrayOfNulls<String>(0)
            println(empty.size)

            val source = arrayOf("spread", "values")
            val spread = AtomicArray(source)
            println(spread.size)
            println(spread.loadAt(0))
            println(spread.loadAt(1))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayOfFactory", expected: "2\nfirst\nvalue\nnext\n0\n2\nspread\nvalues\n")
    }

    @Test
    func testCodegenAtomicArrayUpdateAndFetchAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val arr = atomicArrayOfNulls<String>(1)
            arr.storeAt(0, "a")
            val new = arr.updateAndFetchAt(0) { (it ?: "") + "b" }
            println(new)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicArrayUpdateAndFetchAt", expected: "ab\nab\n")
    }

    @Test
    func testCodegenAtomicIntArrayBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(3)
            println(arr.size)
            println(arr.loadAt(0))
            arr.storeAt(1, 42)
            println(arr.loadAt(1))
            println(arr.exchangeAt(1, 99))
            println(arr.loadAt(1))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayBasic", expected: "3\n0\n42\n42\n99\n")
    }

    @Test
    func testCodegenAtomicIntArrayInitFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(3) { it }
            println(arr.size)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
            println(arr.loadAt(2))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayInitFactory", expected: "3\n0\n1\n2\n")
    }

    @Test
    func testCodegenAtomicIntArrayCASOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(2)
            arr.storeAt(0, 10)
            println(arr.compareAndSetAt(0, 10, 20))
            println(arr.loadAt(0))
            println(arr.compareAndSetAt(0, 99, 30))
            println(arr.loadAt(0))
            println(arr.compareAndExchangeAt(0, 20, 50))
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayCAS", expected: "true\n20\nfalse\n20\n20\n50\n")
    }

    @Test
    func testCodegenAtomicIntArrayArithmeticOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(1)
            println(arr.addAndFetchAt(0, 5))
            println(arr.fetchAndAddAt(0, 3))
            println(arr.loadAt(0))
            println(arr.fetchAndIncrementAt(0))
            println(arr.loadAt(0))
            println(arr.incrementAndFetchAt(0))
            println(arr.loadAt(0))
            println(arr.fetchAndDecrementAt(0))
            println(arr.loadAt(0))
            println(arr.decrementAndFetchAt(0))
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayArithmetic", expected: "5\n5\n8\n8\n9\n10\n10\n10\n9\n8\n8\n")
    }

    @Test
    func testCodegenAtomicIntArrayInt32OverflowPreservesCASSemantics() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(1)
            arr.storeAt(0, Int.MAX_VALUE)
            println(arr.incrementAndFetchAt(0))
            println(arr.compareAndSetAt(0, Int.MIN_VALUE, 5))
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayInt32Overflow", expected: "-2147483648\ntrue\n5\n")
    }

    @Test
    func testCodegenAtomicIntArrayFetchAndUpdateAt() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(1)
            arr.storeAt(0, 10)
            val old = arr.fetchAndUpdateAt(0) { it * 2 }
            println(old)
            println(arr.loadAt(0))
            val fetched = arr.fetchAndUpdateAt(0) { it - 5 }
            println(fetched)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayFetchAndUpdateAt", expected: "10\n20\n20\n15\n")
    }

    @Test
    func testCodegenAtomicIntArrayIndexedStoreLoad() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val arr = AtomicIntArray(2)
            arr.storeAt(0, 7)
            arr.storeAt(1, 13)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayIndexOp", expected: "7\n13\n")
    }

    @Test
    func testCodegenAtomicLongArrayBasicOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(3)
            println(arr.size)
            println(arr.loadAt(0))
            arr.storeAt(2, 100L)
            println(arr.loadAt(2))
            println(arr.exchangeAt(2, 200L))
            println(arr.loadAt(2))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayBasic", expected: "3\n0\n100\n100\n200\n")
    }

    @Test
    func testCodegenAtomicLongArrayInitFactory() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(3) { index ->
                if (index == 0) 10L else if (index == 1) 20L else 30L
            }
            println(arr.size)
            println(arr.loadAt(0))
            println(arr.loadAt(1))
            println(arr.loadAt(2))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayInitFactory", expected: "3\n10\n20\n30\n")
    }

    @Test
    func testCodegenAtomicLongArrayCASOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            arr.storeAt(0, 10L)
            println(arr.compareAndSetAt(0, 10L, 20L))
            println(arr.loadAt(0))
            println(arr.compareAndSetAt(0, 99L, 30L))
            println(arr.loadAt(0))
            println(arr.compareAndExchangeAt(0, 20L, 50L))
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayCAS", expected: "true\n20\nfalse\n20\n20\n50\n")
    }

    @Test
    func testCodegenAtomicLongArrayArithmeticOperations() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            println(arr.addAndFetchAt(0, 5L))
            println(arr.fetchAndAddAt(0, 3L))
            println(arr.loadAt(0))
            println(arr.fetchAndIncrementAt(0))
            println(arr.loadAt(0))
            println(arr.incrementAndFetchAt(0))
            println(arr.fetchAndDecrementAt(0))
            println(arr.loadAt(0))
            println(arr.decrementAndFetchAt(0))
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayArithmetic", expected: "5\n5\n8\n8\n9\n10\n10\n9\n8\n8\n")
    }

    @Test
    func testCodegenAtomicLongArrayFetchAndUpdateAtThirdScenario() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            arr.storeAt(0, 7L)
            val old = arr.fetchAndUpdateAt(0) { it * 3L }
            println(old)
            println(arr.loadAt(0))
            val fetched = arr.fetchAndUpdateAt(0) { it - 4L }
            println(fetched)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayFetchAndUpdateAt", expected: "7\n21\n21\n17\n")
    }

    @Test
    func testCodegenAtomicIncrementAndFetchOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.incrementAndFetch())
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.incrementAndFetch())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.incrementAndFetchAt(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.incrementAndFetchAt(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIncrementAndGet", expected: "2\n2\n4\n4\n6\n6\n8\n8\n")
    }

    @Test
    func testCodegenAtomicLongArrayFetchAndUpdateAtSecondScenario() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val arr = AtomicLongArray(1)
            arr.storeAt(0, 10L)
            val old = arr.fetchAndUpdateAt(0) { it * 2L }
            println(old)
            println(arr.loadAt(0))
            val fetched = arr.fetchAndUpdateAt(0) { it - 5L }
            println(fetched)
            println(arr.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayFetchAndUpdateAt", expected: "10\n20\n20\n15\n")
    }

    @Test
    func testCodegenAtomicFetchAndIncrementOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.fetchAndIncrement())
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.fetchAndIncrement())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.fetchAndIncrementAt(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.fetchAndIncrementAt(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndIncrement", expected: "1\n2\n3\n4\n5\n6\n7\n8\n")
    }

    @Test
    func testCodegenAtomicFetchAndDecrementOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(2)
            println(intValue.fetchAndDecrement())
            println(intValue.load())

            val longValue = AtomicLong(4L)
            println(longValue.fetchAndDecrement())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 6)
            println(intArray.fetchAndDecrementAt(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 8L)
            println(longArray.fetchAndDecrementAt(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndDecrement", expected: "2\n1\n4\n3\n6\n5\n8\n7\n")
    }

    @Test
    func testCodegenAtomicFetchAndAddOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.fetchAndAdd(2))
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.fetchAndAdd(4L))
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.fetchAndAddAt(0, 2))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.fetchAndAddAt(0, 3L))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndAdd", expected: "1\n3\n3\n7\n5\n7\n7\n10\n")
    }

    @Test
    func testCodegenAtomicDecrementAndFetchOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(2)
            println(intValue.decrementAndFetch())
            println(intValue.load())

            val longValue = AtomicLong(4L)
            println(longValue.decrementAndFetch())
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 6)
            println(intArray.decrementAndFetchAt(0))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 8L)
            println(longArray.decrementAndFetchAt(0))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicDecrementAndGet", expected: "1\n1\n3\n3\n5\n5\n7\n7\n")
    }

    @Test
    func testCodegenAtomicAddAndFetchOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.addAndFetch(2))
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.addAndFetch(4L))
            println(longValue.load())

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.addAndFetchAt(0, 2))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.addAndFetchAt(0, 3L))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicAddAndGet", expected: "3\n3\n7\n7\n7\n7\n10\n10\n")
    }

    @Test
    func testCodegenAtomicIntDefaultInitialValue() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntDefaultInit", expected: "0\n")
    }

    @Test
    func testCodegenAtomicIntUpdateFamily() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.update

        fun main() {
            val a = AtomicInt(10)
            a.update { it * 2 }
            println(a.load())
            val fetched = a.fetchAndUpdate { it - 3 }
            println(fetched)
            println(a.load())
            val new2 = a.updateAndFetch { it + 5 }
            println(new2)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntGetAndUpdate", expected: "20\n20\n17\n22\n22\n")
    }

    @Test
    func testCodegenAtomicLongUpdateFamily() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.update

        fun main() {
            val a = AtomicLong(10L)
            a.update { it * 2L }
            println(a.load())
            val fetched = a.fetchAndUpdate { it - 3L }
            println(fetched)
            println(a.load())
            val new2 = a.updateAndFetch { it + 5L }
            println(new2)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongGetAndUpdate", expected: "20\n20\n17\n22\n22\n")
    }

    @Test
    func testCodegenAtomicExchangeOverloads() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLong
        import kotlin.concurrent.atomics.AtomicLongArray
        import kotlin.concurrent.atomics.AtomicReference
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main() {
            val intValue = AtomicInt(1)
            println(intValue.exchange(2))
            println(intValue.load())

            val longValue = AtomicLong(3L)
            println(longValue.exchange(4L))
            println(longValue.load())

            val refValue = AtomicReference("a")
            println(refValue.exchange("b"))
            println(refValue.load())

            val refArray = atomicArrayOfNulls<String>(1)
            refArray.storeAt(0, "x")
            println(refArray.exchangeAt(0, "y"))
            println(refArray.loadAt(0))

            val intArray = AtomicIntArray(1)
            intArray.storeAt(0, 5)
            println(intArray.exchangeAt(0, 6))
            println(intArray.loadAt(0))

            val longArray = AtomicLongArray(1)
            longArray.storeAt(0, 7L)
            println(longArray.exchangeAt(0, 8L))
            println(longArray.loadAt(0))
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicGetAndSet", expected: "1\n2\n3\n4\na\nb\nx\ny\n5\n6\n7\n8\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicIntLoadStore() throws {
        let source = """
        import kotlin.concurrent.AtomicInt

        fun main() {
            val a = AtomicInt(5)
            println(a.load())
            a.store(10)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicInt", expected: "5\n10\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicLongOperations() throws {
        let source = """
        import kotlin.concurrent.AtomicLong

        fun main() {
            val value = AtomicLong(5L)
            println(value.load())
            value.store(10L)
            println(value.load())
            println(value.addAndFetch(2L))
        }
        """
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicLong", expected: "5\n10\n12\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicReferenceOperations() throws {
        let source = """
        import kotlin.concurrent.AtomicReference

        fun main() {
            val ref = AtomicReference("first")
            println(ref.load())
            ref.store("second")
            println(ref.exchange("third"))
            println(ref.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicReference", expected: "first\nsecond\nthird\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicIntArrayOperations() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.concurrent.AtomicIntArray

        fun main() {
            val values = AtomicIntArray(2)
            values.storeAt(0, 10)
            values[1] = 20
            println(values.loadAt(0))
            println(values[1])
            println(values.addAndFetchAt(0, 5))
            println(values.size)
        }
        """
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicIntArray", expected: "10\n20\n15\n2\n")
    }

    @Test
    func testCodegenKotlinConcurrentAtomicLongArrayOperations() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.concurrent.AtomicLongArray

        fun main() {
            val values = AtomicLongArray(2)
            values.storeAt(0, 10L)
            values[1] = 20L
            println(values.loadAt(0))
            println(values[1])
            println(values.addAndFetchAt(0, 5L))
            println(values.size)
        }
        """
        try assertKotlinOutput(source, moduleName: "KConcurrentAtomicLongArray", expected: "10\n20\n15\n2\n")
    }

    @Test
    func testCodegenAtomicBooleanValueSetterWiresBoolStore() throws {
        let source = """
        import kotlin.concurrent.AtomicBoolean

        fun main() {
            val a = AtomicBoolean(false)
            a.value = true
            println(a.value)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicBoolSetterABI001", expected: "true\n")
    }

    @Test
    func testCodegenAtomicIntValueSetterWiresIntStore() throws {
        let source = """
        import kotlin.concurrent.AtomicInt

        fun main() {
            val a = AtomicInt(0)
            a.value = 42
            println(a.value)
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntSetterABI001", expected: "42\n")
    }

    @Test
    func testCodegenAtomicReferenceUpdateFamily() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference
        import kotlin.concurrent.atomics.update

        fun main() {
            val a = AtomicReference("hello")
            a.update { it + "!" }
            println(a.load())
            val fetched = a.fetchAndUpdate { it + "?" }
            println(fetched)
            println(a.load())
            val fetchedNew = a.updateAndFetch { it.uppercase() + "~" }
            println(fetchedNew)
            println(a.load())
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicRefGetAndUpdateBUG01", expected: "hello!\nhello!\nhello!?\nHELLO!?~\nHELLO!?~\n")
    }

    @Test
    func testCodegenAtomicIntArrayOOBLoadThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val a = AtomicIntArray(3)
            try {
                val _ = a.loadAt(5)
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayOOBLoad", expected: "caught\n")
    }

    @Test
    func testCodegenAtomicIntArrayOOBStoreThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicIntArray

        fun main() {
            val a = AtomicIntArray(3)
            try {
                a.storeAt(10, 99)
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicIntArrayOOBStore", expected: "caught\n")
    }

    @Test
    func testCodegenAtomicLongArrayOOBLoadThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val a = AtomicLongArray(2)
            try {
                val _ = a.loadAt(7)
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayOOBLoad", expected: "caught\n")
    }

    @Test
    func testCodegenAtomicLongArrayOOBStoreThrowsIndexOutOfBounds() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val a = AtomicLongArray(2)
            try {
                a.storeAt(99, 1L)
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "AtomicLongArrayOOBStore", expected: "caught\n")
    }

    @Test
    func testCodegenAtomicArrayOfBoxesPrimitiveElementsForIsChecks() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicArray

        fun main() {
            val mixed = AtomicArray(arrayOf<Any>(1.5, "x", 2.5, 7L, true))
            for (i in 0 until mixed.size) {
                val v = mixed.loadAt(i)
                println("${v is Double} ${v is Long} ${v is Boolean} ${v is String}")
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AtomicArrayOfBoxesPrimitives",
            expected:
                """
                true false false false
                false false false true
                true false false false
                false true false false
                false false true false
                """ + "\n"
        )
    }

    @Test
    func testCodegenNativeConcurrentAtomicReferenceBasicOperations() throws {
        let source = """
        import kotlin.native.concurrent.AtomicReference

        class Item(val name: String)

        fun main() {
            val a = Item("A")
            val b = Item("B")
            val c = Item("C")
            val ref = AtomicReference(a)

            println(ref.value.name)
            ref.value = b
            println(ref.value.name)

            val old = ref.getAndSet(c)
            println(old.name)
            println(ref.value.name)

            val cas1 = ref.compareAndSwap(c, a)
            println(cas1 === c)
            println(ref.value === a)

            val cas2 = ref.compareAndSwap(b, c)
            println(cas2 === a)
            println(ref.value === a)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NativeConcurrentAtomicReferenceOps",
            expected:
                """
                A
                B
                B
                C
                true
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenNativeConcurrentFreezableAtomicReferenceBasicOperations() throws {
        let source = """
        import kotlin.native.concurrent.FreezableAtomicReference

        class Item(val name: String)

        fun main() {
            val a = Item("A")
            val b = Item("B")
            val c = Item("C")
            val ref = FreezableAtomicReference(a)

            println(ref.value.name)
            ref.value = b
            println(ref.value.name)

            val casSetSuccess = ref.compareAndSet(b, c)
            println(casSetSuccess)
            println(ref.value === c)

            val casSetFail = ref.compareAndSet(b, a)
            println(casSetFail)
            println(ref.value === c)

            val casSwapSuccess = ref.compareAndSwap(c, a)
            println(casSwapSuccess === c)
            println(ref.value === a)

            val casSwapFail = ref.compareAndSwap(b, c)
            println(casSwapFail === a)
            println(ref.value === a)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NativeConcurrentFreezableAtomicReferenceOps",
            expected:
                """
                A
                B
                true
                true
                false
                true
                true
                true
                true
                true
                """ + "\n"
        )
    }

}
#endif
