#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {

    /// Built once per process: `static let` initializes under `swift_once`, so
    /// parallel tests share a single compile. The previous check-then-set over
    /// a mutable static allowed concurrent tests to each miss the cache and
    /// re-pay the bundled-stdlib compile.
    private static nonisolated(unsafe) let _sharedNativePlatformMemoryModelKIRCtx = Result<CompilationContext, any Error> {
        // Keep this synthetic object-property fixture isolated; combining it with the other native bridge fixtures drops the runtime call from KIR.
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun main(): kotlin.native.MemoryModel = Platform.memoryModel
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        return ctx
    }

    private func sharedNativePlatformMemoryModelKIRCtx() throws -> CompilationContext {
        try Self._sharedNativePlatformMemoryModelKIRCtx.get()
    }

    /// Built once per process: `static let` initializes under `swift_once`, so
    /// parallel tests share a single compile. The previous check-then-set over
    /// a mutable static allowed concurrent tests to each miss the cache and
    /// re-pay the bundled-stdlib compile.
    private static nonisolated(unsafe) let _sharedNativePlatformKIRCtx = Result<CompilationContext, any Error> {
        let sources: [String] = [
            """
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase1

            import kotlin.native.identityHashCode

            fun probe1(value: Any?): Int = value.identityHashCode()
            """,
            """
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase2

            import kotlin.native.getStackTraceAddresses

            class TestThrowable : Throwable()

            fun probe2(throwable: Throwable): List<Long> = throwable.getStackTraceAddresses()
            fun probe2Subclass(): List<Long> = TestThrowable().getStackTraceAddresses()
            """,
            """
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase3

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
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase4

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
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase5

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
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
            package nativecase6

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
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
            package nativecase7

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
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase8

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
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            package nativecase9

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
            package nativecase10

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.IntVar
            import kotlinx.cinterop.toKStringFromUtf32

            fun decode10(p: CPointer<IntVar>): String = p.toKStringFromUtf32()
            """,
            """
            package nativecase11

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.ShortVar
            import kotlinx.cinterop.toKString

            fun decode11(p: CPointer<ShortVar>): String = p.toKString()
            """,
            """
            package nativecase12

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.UShortVar
            import kotlinx.cinterop.toKStringFromUtf16

            fun decode12(p: CPointer<UShortVar>): String = p.toKStringFromUtf16()
            """,
            """
            package nativecase13

            import kotlinx.cinterop.CPointer
            import kotlinx.cinterop.UShortVar
            import kotlinx.cinterop.toKString

            fun decode13(p: CPointer<UShortVar>): String = p.toKString()
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runToKIR(ctx)

        return ctx
    }

    private func sharedNativePlatformKIRCtx() throws -> CompilationContext {
        try Self._sharedNativePlatformKIRCtx.get()
    }

    /// Built once per process: `static let` initializes under `swift_once`, so
    /// parallel tests share a single compile. The previous check-then-set over
    /// a mutable static allowed concurrent tests to each miss the cache and
    /// re-pay the bundled-stdlib compile.
    private static nonisolated(unsafe) let _sharedNativePlatformAllAPIsKIRCtx = Result<CompilationContext, any Error> {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:Suppress("DEPRECATION")

        import kotlin.native.Platform

        fun allPlatformAPIs(): Int {
            val unaligned = Platform.canAccessUnaligned
            val littleEndian = Platform.isLittleEndian
            val osFamily = Platform.osFamily
            val cpuArchitecture = Platform.cpuArchitecture
            val memoryModel = Platform.memoryModel
            val debugBinary = Platform.isDebugBinary
            val programName = Platform.programName
            val leakChecker = Platform.isMemoryLeakCheckerActive
            Platform.isMemoryLeakCheckerActive = !leakChecker
            val processors = Platform.getAvailableProcessors()
            return processors +
                if (unaligned || littleEndian || debugBinary || programName != null) 1 else 0 +
                if (osFamily == osFamily && cpuArchitecture == cpuArchitecture && memoryModel == memoryModel) 1 else 0
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        return ctx
    }

    private func sharedNativePlatformAllAPIsKIRCtx() throws -> CompilationContext {
        try Self._sharedNativePlatformAllAPIsKIRCtx.get()
    }

    @Test func testNativePlatformMemoryModelUsesTheCurrentConstant() throws {
        let ctx = try sharedNativePlatformMemoryModelKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(!callees.contains(runtimeCallee(.platformMemoryModel)))
    }
    @Test func testABILoweringMarksNativePlatformMemoryModelAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(
            callees.contains(interner.intern(runtimeCallee(.platformMemoryModel))),
            "The platform memory-model bridge must not receive an outThrown slot during ABI lowering"
        )
    }

    @Test func testNativePlatformAPIsLowerToBundledSourceLayer() throws {
        let ctx = try sharedNativePlatformAllAPIsKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "allPlatformAPIs", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("getAvailableProcessors"))
        #expect(callees.contains("set"), "Expected the source-backed Platform var setter call")
        #expect(Set(callees).isDisjoint(with: runtimeCallees(in: .platform)))
        try expectResolvedKIRCallTargets(in: body, context: ctx)
    }

    @Test func testABILoweringMarksNativePlatformRuntimeBridgesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        for callee in [
            runtimeCallee(.platformCanAccessUnaligned),
            runtimeCallee(.platformIsLittleEndian),
            runtimeCallee(.platformOsFamily),
            runtimeCallee(.platformCpuArchitecture),
            runtimeCallee(.platformMemoryModel),
            runtimeCallee(.platformIsDebugBinary),
            runtimeCallee(.platformProgramName),
            runtimeCallee(.platformIsMemoryLeakCheckerActiveLoad),
            runtimeCallee(.platformIsMemoryLeakCheckerActiveStore),
            runtimeCallee(.platformGetAvailableProcessorsEnv),
            runtimeCallee(.platformGetAvailableProcessors),
        ] {
            #expect(callees.contains(interner.intern(callee)), "Expected non-throwing ABI entry for \(callee)")
        }
    }

    @Test func testNativeIdentityHashCodeLowersToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe1", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeIdentityHashCode)))
    }
    @Test func testABILoweringMarksNativeIdentityHashCodeAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeIdentityHashCode))))
    }

    @Test func testNativeGetStackTraceAddressesLowersToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe2", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeGetStackTraceAddresses)))
    }
    @Test func testThrowableSubclassCaptureLowersBeforeStackTraceAddressLookup() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe2Subclass", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.throwableCaptureStackTrace)))
        #expect(callees.contains(runtimeCallee(.nativeGetStackTraceAddresses)))
    }
    @Test func testABILoweringMarksNativeGetStackTraceAddressesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeGetStackTraceAddresses))))
    }

    @Test func testNativeUnhandledExceptionHooksLowerToRuntimeCallees() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let probeBody = try findKIRFunctionBody(named: "probe3", in: module, interner: ctx.interner)
        let dieBody = try findKIRFunctionBody(named: "die3", in: module, interner: ctx.interner)
        let callees = extractCallees(from: probeBody, interner: ctx.interner)
            + extractCallees(from: dieBody, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeGetUnhandledExceptionHook)))
        #expect(callees.contains(runtimeCallee(.nativeSetUnhandledExceptionHook)))
        #expect(callees.contains(runtimeCallee(.nativeProcessUnhandledException)))
        #expect(callees.contains(runtimeCallee(.nativeTerminateWithUnhandledException)))
    }
    @Test func testABILoweringMarksNonThrowingNativeUnhandledExceptionHooks() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeGetUnhandledExceptionHook))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeSetUnhandledExceptionHook))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeTerminateWithUnhandledException))))
        #expect(!(callees.contains(interner.intern(runtimeCallee(.nativeProcessUnhandledException)))))
    }

    @Test func testNativeByteArrayAccessorsLowerToRuntimeCallees() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe4", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetByteAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetShortAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetIntAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetLongAt)))
    }
    @Test func testABILoweringMarksNativeByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetByteAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetShortAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetIntAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetLongAt))))
    }

    @Test func testNativeByteArraySettersLowerToRuntimeCallees() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe5", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeByteArraySetByteAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetShortAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetIntAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetLongAt)))
    }
    @Test func testABILoweringMarksNativeByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetByteAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetShortAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetIntAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetLongAt))))
    }

    @Test func testNativeUnsignedByteArrayAccessorsLowerToRuntimeCallees() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe6", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetUByteAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetUShortAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetUIntAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetULongAt)))
    }
    @Test func testABILoweringMarksNativeUnsignedByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetUByteAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetUShortAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetUIntAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetULongAt))))
    }

    @Test func testNativeUnsignedByteArraySettersLowerToRuntimeCallees() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe7", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeByteArraySetUByteAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetUShortAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetUIntAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetULongAt)))
    }
    @Test func testABILoweringMarksNativeUnsignedByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetUByteAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetUShortAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetUIntAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetULongAt))))
    }

    @Test func testNativePrimitiveByteArrayAccessorsLowerToRuntimeCallees() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe8", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetCharAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetFloatAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArrayGetDoubleAt)))
    }
    @Test func testABILoweringMarksNativePrimitiveByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetCharAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetFloatAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArrayGetDoubleAt))))
    }

    @Test func testNativePrimitiveByteArraySettersLowerToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe9", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.nativeByteArraySetCharAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetFloatAt)))
        #expect(callees.contains(runtimeCallee(.nativeByteArraySetDoubleAt)))
    }
    @Test func testABILoweringMarksNativePrimitiveByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetCharAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetFloatAt))))
        #expect(callees.contains(interner.intern(runtimeCallee(.nativeByteArraySetDoubleAt))))
    }

    @Test func testCPointerIntVarToKStringFromUtf32LowersToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "decode10", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(
            callees.contains(runtimeCallee(.cpointerToKStringFromUtf32)),
            "Expected kk_cpointer_toKStringFromUtf32 runtime call in KIR"
        )
    }
    @Test func testCPointerShortVarToKStringLowersToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "decode11", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(
            callees.contains(runtimeCallee(.cpointerToKStringFromUtf16)),
            "Expected kk_cpointer_toKStringFromUtf16 runtime call in KIR"
        )
    }
    @Test func testCPointerUShortVarToKStringFromUtf16LowersToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "decode12", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(
            callees.contains(runtimeCallee(.cpointerToKStringFromUtf16)),
            "Expected kk_cpointer_toKStringFromUtf16 runtime call in KIR"
        )
    }
    @Test func testCPointerUShortVarToKStringLowersToRuntimeCallee() throws {
        let ctx = try sharedNativePlatformKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "decode13", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(
            callees.contains(runtimeCallee(.cpointerToKStringFromUtf16)),
            "Expected CPointer<UShortVar>.toKString() to lower to kk_cpointer_toKStringFromUtf16"
        )
    }
}
#endif
