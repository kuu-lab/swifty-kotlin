#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testNativePlatformMemoryModelLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun main() {
            val memoryModel = Platform.memoryModel
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_platform_memoryModel"),
                "Expected Platform.memoryModel runtime call"
            )
        }
    }

    @Test func testABILoweringMarksNativePlatformMemoryModelAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(
            callees.contains(interner.intern("kk_platform_memoryModel")),
            "kk_platform_memoryModel should not receive an outThrown slot during ABI lowering"
        )
    }

    @Test func testNativeIdentityHashCodeLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.identityHashCode

        fun probe(value: Any?): Int = value.identityHashCode()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_identityHashCode"))
        }
    }

    @Test func testABILoweringMarksNativeIdentityHashCodeAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_identityHashCode")))
    }

    @Test func testNativeGetStackTraceAddressesLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getStackTraceAddresses

        fun probe(): List<Long> = getStackTraceAddresses()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_getStackTraceAddresses"))
        }
    }

    @Test func testABILoweringMarksNativeGetStackTraceAddressesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_getStackTraceAddresses")))
    }

    @Test func testNativeUnhandledExceptionHooksLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getUnhandledExceptionHook
        import kotlin.native.setUnhandledExceptionHook
        import kotlin.native.processUnhandledException
        import kotlin.native.terminateWithUnhandledException

        fun probe(throwable: Throwable) {
            val hook = getUnhandledExceptionHook()
            setUnhandledExceptionHook(hook)
            processUnhandledException(throwable)
        }

        fun die(throwable: Throwable): Nothing = terminateWithUnhandledException(throwable)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let probeBody = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let dieBody = try findKIRFunctionBody(named: "die", in: module, interner: ctx.interner)
            let callees = extractCallees(from: probeBody, interner: ctx.interner)
                + extractCallees(from: dieBody, interner: ctx.interner)

            #expect(callees.contains("kk_native_getUnhandledExceptionHook"))
            #expect(callees.contains("kk_native_setUnhandledExceptionHook"))
            #expect(callees.contains("kk_native_processUnhandledException"))
            #expect(callees.contains("kk_native_terminateWithUnhandledException"))
        }
    }

    @Test func testABILoweringMarksNonThrowingNativeUnhandledExceptionHooks() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_getUnhandledExceptionHook")))
        #expect(callees.contains(interner.intern("kk_native_setUnhandledExceptionHook")))
        #expect(callees.contains(interner.intern("kk_native_terminateWithUnhandledException")))
        #expect(!(callees.contains(interner.intern("kk_native_processUnhandledException"))))
    }

    @Test func testNativeByteArrayAccessorsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getByteAt
        import kotlin.native.getShortAt
        import kotlin.native.getIntAt
        import kotlin.native.getLongAt

        fun probe(bytes: ByteArray): Long {
            val byteValue = bytes.getByteAt(0)
            val shortValue = bytes.getShortAt(1)
            val intValue = bytes.getIntAt(2)
            return bytes.getLongAt(0) + byteValue + shortValue + intValue
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_byteArray_getByteAt"))
            #expect(callees.contains("kk_native_byteArray_getShortAt"))
            #expect(callees.contains("kk_native_byteArray_getIntAt"))
            #expect(callees.contains("kk_native_byteArray_getLongAt"))
        }
    }

    @Test func testABILoweringMarksNativeByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_byteArray_getByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getLongAt")))
    }

    @Test func testNativeByteArraySettersLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.setByteAt
        import kotlin.native.setShortAt
        import kotlin.native.setIntAt
        import kotlin.native.setLongAt

        fun probe(bytes: ByteArray) {
            bytes.setByteAt(0, -1)
            bytes.setShortAt(1, 0x1234)
            bytes.setIntAt(2, 0x12345678)
            bytes.setLongAt(0, 42L)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_byteArray_setByteAt"))
            #expect(callees.contains("kk_native_byteArray_setShortAt"))
            #expect(callees.contains("kk_native_byteArray_setIntAt"))
            #expect(callees.contains("kk_native_byteArray_setLongAt"))
        }
    }

    @Test func testABILoweringMarksNativeByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_byteArray_setByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setLongAt")))
    }

    @Test func testNativeUnsignedByteArrayAccessorsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

        import kotlin.native.getUByteAt
        import kotlin.native.getUShortAt
        import kotlin.native.getUIntAt
        import kotlin.native.getULongAt

        fun probe(bytes: ByteArray) {
            bytes.getUByteAt(0)
            bytes.getUShortAt(1)
            bytes.getUIntAt(2)
            bytes.getULongAt(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_byteArray_getUByteAt"))
            #expect(callees.contains("kk_native_byteArray_getUShortAt"))
            #expect(callees.contains("kk_native_byteArray_getUIntAt"))
            #expect(callees.contains("kk_native_byteArray_getULongAt"))
        }
    }

    @Test func testABILoweringMarksNativeUnsignedByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_byteArray_getUByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getUShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getUIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getULongAt")))
    }

    @Test func testNativeUnsignedByteArraySettersLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

        import kotlin.native.setUByteAt
        import kotlin.native.setUShortAt
        import kotlin.native.setUIntAt
        import kotlin.native.setULongAt

        fun probe(bytes: ByteArray, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            bytes.setUByteAt(0, ub)
            bytes.setUShortAt(1, us)
            bytes.setUIntAt(2, ui)
            bytes.setULongAt(0, ul)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_byteArray_setUByteAt"))
            #expect(callees.contains("kk_native_byteArray_setUShortAt"))
            #expect(callees.contains("kk_native_byteArray_setUIntAt"))
            #expect(callees.contains("kk_native_byteArray_setULongAt"))
        }
    }

    @Test func testABILoweringMarksNativeUnsignedByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_byteArray_setUByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setUShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setUIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setULongAt")))
    }

    @Test func testNativePrimitiveByteArrayAccessorsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getCharAt
        import kotlin.native.getFloatAt
        import kotlin.native.getDoubleAt

        fun probe(bytes: ByteArray) {
            bytes.getCharAt(0)
            bytes.getFloatAt(2)
            bytes.getDoubleAt(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_byteArray_getCharAt"))
            #expect(callees.contains("kk_native_byteArray_getFloatAt"))
            #expect(callees.contains("kk_native_byteArray_getDoubleAt"))
        }
    }

    @Test func testABILoweringMarksNativePrimitiveByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_byteArray_getCharAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getFloatAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getDoubleAt")))
    }

    @Test func testNativePrimitiveByteArraySettersLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.setCharAt
        import kotlin.native.setFloatAt
        import kotlin.native.setDoubleAt

        fun probe(bytes: ByteArray, c: Char, f: Float, d: Double) {
            bytes.setCharAt(0, c)
            bytes.setFloatAt(2, f)
            bytes.setDoubleAt(0, d)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_native_byteArray_setCharAt"))
            #expect(callees.contains("kk_native_byteArray_setFloatAt"))
            #expect(callees.contains("kk_native_byteArray_setDoubleAt"))
        }
    }

    @Test func testABILoweringMarksNativePrimitiveByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_native_byteArray_setCharAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setFloatAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setDoubleAt")))
    }

    @Test func testCPointerIntVarToKStringFromUtf32LowersToRuntimeCallee() throws {
        let source = """
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.IntVar
        import kotlinx.cinterop.toKStringFromUtf32

        fun decode(p: CPointer<IntVar>): String = p.toKStringFromUtf32()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "decode", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_cpointer_toKStringFromUtf32"),
                "Expected kk_cpointer_toKStringFromUtf32 runtime call in KIR"
            )
        }
    }

    @Test func testCPointerShortVarToKStringLowersToRuntimeCallee() throws {
        let source = """
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.ShortVar
        import kotlinx.cinterop.toKString

        fun decode(p: CPointer<ShortVar>): String = p.toKString()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "decode", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_cpointer_toKStringFromUtf16"),
                "Expected kk_cpointer_toKStringFromUtf16 runtime call in KIR"
            )
        }
    }

    @Test func testCPointerUShortVarToKStringFromUtf16LowersToRuntimeCallee() throws {
        let source = """
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.UShortVar
        import kotlinx.cinterop.toKStringFromUtf16

        fun decode(p: CPointer<UShortVar>): String = p.toKStringFromUtf16()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "decode", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_cpointer_toKStringFromUtf16"),
                "Expected kk_cpointer_toKStringFromUtf16 runtime call in KIR"
            )
        }
    }

    @Test func testCPointerUShortVarToKStringLowersToRuntimeCallee() throws {
        // STDLIB-CINTEROP-FN-032: toKString() on CPointer<UShortVar> is an alias
        // for toKStringFromUtf16() and must reuse the same runtime decoder.
        let source = """
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.UShortVar
        import kotlinx.cinterop.toKString

        fun decode(p: CPointer<UShortVar>): String = p.toKString()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "decode", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_cpointer_toKStringFromUtf16"),
                "Expected CPointer<UShortVar>.toKString() to lower to kk_cpointer_toKStringFromUtf16"
            )
        }
    }
}
#endif
