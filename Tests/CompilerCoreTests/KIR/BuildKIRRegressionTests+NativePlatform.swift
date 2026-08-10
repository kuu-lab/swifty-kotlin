#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testNativePlatformRuntimeCallees() throws {
        let sources = [
            // Keep the Platform.memoryModel scenario in the default package with
            // `fun main()` so the compiler lowers the property access to a
            // `kk_platform_memoryModel` runtime call inside the entry point.
            """
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.Platform

            fun main() {
                val memoryModel = Platform.memoryModel
            }
            """,
            """
            package sample1
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.identityHashCode

            fun probe1(value: Any?): Int = value.identityHashCode()
            """,
            """
            package sample2
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.getStackTraceAddresses

            fun probe2(): List<Long> = getStackTraceAddresses()
            """,
            """
            package sample3
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.getUnhandledExceptionHook
            import kotlin.native.setUnhandledExceptionHook
            import kotlin.native.processUnhandledException
            import kotlin.native.terminateWithUnhandledException

            fun probe3(throwable: Throwable) {
                val hook = getUnhandledExceptionHook()
                setUnhandledExceptionHook(hook)
                processUnhandledException(throwable)
            }

            fun die3(throwable: Throwable): Nothing = terminateWithUnhandledException(throwable)
            """,
            """
            package sample4
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.getByteAt
            import kotlin.native.getShortAt
            import kotlin.native.getIntAt
            import kotlin.native.getLongAt

            fun probe4(bytes: ByteArray): Long {
                val byteValue = bytes.getByteAt(0)
                val shortValue = bytes.getShortAt(1)
                val intValue = bytes.getIntAt(2)
                return bytes.getLongAt(0) + byteValue + shortValue + intValue
            }
            """,
            """
            package sample5
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.setByteAt
            import kotlin.native.setShortAt
            import kotlin.native.setIntAt
            import kotlin.native.setLongAt

            fun probe5(bytes: ByteArray) {
                bytes.setByteAt(0, -1)
                bytes.setShortAt(1, 0x1234)
                bytes.setIntAt(2, 0x12345678)
                bytes.setLongAt(0, 42L)
            }
            """,
            """
            package sample6
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

            import kotlin.native.getUByteAt
            import kotlin.native.getUShortAt
            import kotlin.native.getUIntAt
            import kotlin.native.getULongAt

            fun probe6(bytes: ByteArray) {
                bytes.getUByteAt(0)
                bytes.getUShortAt(1)
                bytes.getUIntAt(2)
                bytes.getULongAt(0)
            }
            """,
            """
            package sample7
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

            import kotlin.native.setUByteAt
            import kotlin.native.setUShortAt
            import kotlin.native.setUIntAt
            import kotlin.native.setULongAt

            fun probe7(bytes: ByteArray, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
                bytes.setUByteAt(0, ub)
                bytes.setUShortAt(1, us)
                bytes.setUIntAt(2, ui)
                bytes.setULongAt(0, ul)
            }
            """,
            """
            package sample8
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.getCharAt
            import kotlin.native.getFloatAt
            import kotlin.native.getDoubleAt

            fun probe8(bytes: ByteArray) {
                bytes.getCharAt(0)
                bytes.getFloatAt(2)
                bytes.getDoubleAt(0)
            }
            """,
            """
            package sample9
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

            import kotlin.native.setCharAt
            import kotlin.native.setFloatAt
            import kotlin.native.setDoubleAt

            fun probe9(bytes: ByteArray, c: Char, f: Float, d: Double) {
                bytes.setCharAt(0, c)
                bytes.setFloatAt(2, f)
                bytes.setDoubleAt(0, d)
            }
            """,
            """
            package sample10

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.IntVar
            import kotlinx.cinterop.toKStringFromUtf32

            fun decode10(p: CPointer<IntVar>): String = p.toKStringFromUtf32()
            """,
            """
            package sample11

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.ShortVar
            import kotlinx.cinterop.toKString

            fun decode11(p: CPointer<ShortVar>): String = p.toKString()
            """,
            """
            package sample12

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.UShortVar
            import kotlinx.cinterop.toKStringFromUtf16

            fun decode12(p: CPointer<UShortVar>): String = p.toKStringFromUtf16()
            """,
            """
            package sample13

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.UShortVar
            import kotlinx.cinterop.toKString

            fun decode13(p: CPointer<UShortVar>): String = p.toKString()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_platform_memoryModel"), "Expected Platform.memoryModel runtime call")
            }

            do {
                let body = try findKIRFunctionBody(named: "probe1", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_identityHashCode"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe2", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_getStackTraceAddresses"))
            }

            do {
                let probeBody = try findKIRFunctionBody(named: "probe3", in: module, interner: interner)
                let dieBody = try findKIRFunctionBody(named: "die3", in: module, interner: interner)
                let callees = extractCallees(from: probeBody, interner: interner)
                    + extractCallees(from: dieBody, interner: interner)
                #expect(callees.contains("kk_native_getUnhandledExceptionHook"))
                #expect(callees.contains("kk_native_setUnhandledExceptionHook"))
                #expect(callees.contains("kk_native_processUnhandledException"))
                #expect(callees.contains("kk_native_terminateWithUnhandledException"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe4", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_byteArray_getByteAt"))
                #expect(callees.contains("kk_native_byteArray_getShortAt"))
                #expect(callees.contains("kk_native_byteArray_getIntAt"))
                #expect(callees.contains("kk_native_byteArray_getLongAt"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe5", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_byteArray_setByteAt"))
                #expect(callees.contains("kk_native_byteArray_setShortAt"))
                #expect(callees.contains("kk_native_byteArray_setIntAt"))
                #expect(callees.contains("kk_native_byteArray_setLongAt"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe6", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_byteArray_getUByteAt"))
                #expect(callees.contains("kk_native_byteArray_getUShortAt"))
                #expect(callees.contains("kk_native_byteArray_getUIntAt"))
                #expect(callees.contains("kk_native_byteArray_getULongAt"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe7", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_byteArray_setUByteAt"))
                #expect(callees.contains("kk_native_byteArray_setUShortAt"))
                #expect(callees.contains("kk_native_byteArray_setUIntAt"))
                #expect(callees.contains("kk_native_byteArray_setULongAt"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe8", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_byteArray_getCharAt"))
                #expect(callees.contains("kk_native_byteArray_getFloatAt"))
                #expect(callees.contains("kk_native_byteArray_getDoubleAt"))
            }

            do {
                let body = try findKIRFunctionBody(named: "probe9", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_native_byteArray_setCharAt"))
                #expect(callees.contains("kk_native_byteArray_setFloatAt"))
                #expect(callees.contains("kk_native_byteArray_setDoubleAt"))
            }

            do {
                let body = try findKIRFunctionBody(named: "decode10", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_cpointer_toKStringFromUtf32"))
            }

            do {
                let body = try findKIRFunctionBody(named: "decode11", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_cpointer_toKStringFromUtf16"))
            }

            do {
                let body = try findKIRFunctionBody(named: "decode12", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_cpointer_toKStringFromUtf16"))
            }

            do {
                let body = try findKIRFunctionBody(named: "decode13", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_cpointer_toKStringFromUtf16"))
            }
        }
    }

    @Test func testABILoweringMarksNativePlatformCalleesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_platform_memoryModel")))
        #expect(callees.contains(interner.intern("kk_native_identityHashCode")))
        #expect(callees.contains(interner.intern("kk_native_getStackTraceAddresses")))
        #expect(callees.contains(interner.intern("kk_native_getUnhandledExceptionHook")))
        #expect(callees.contains(interner.intern("kk_native_setUnhandledExceptionHook")))
        #expect(callees.contains(interner.intern("kk_native_terminateWithUnhandledException")))
        #expect(!(callees.contains(interner.intern("kk_native_processUnhandledException"))))

        #expect(callees.contains(interner.intern("kk_native_byteArray_getByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getLongAt")))

        #expect(callees.contains(interner.intern("kk_native_byteArray_setByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setLongAt")))

        #expect(callees.contains(interner.intern("kk_native_byteArray_getUByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getUShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getUIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getULongAt")))

        #expect(callees.contains(interner.intern("kk_native_byteArray_setUByteAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setUShortAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setUIntAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setULongAt")))

        #expect(callees.contains(interner.intern("kk_native_byteArray_getCharAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getFloatAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_getDoubleAt")))

        #expect(callees.contains(interner.intern("kk_native_byteArray_setCharAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setFloatAt")))
        #expect(callees.contains(interner.intern("kk_native_byteArray_setDoubleAt")))
    }
}
#endif
