@testable import CompilerCore
import Foundation
import XCTest

final class ConcurrencySyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testThreadClassAndFunctionSignatures() throws {
        let (sema, interner) = try makeSema()

        let threadFQName = ["java", "lang", "Thread"].map { interner.intern($0) }
        let threadSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: threadFQName),
            "Expected java.lang.Thread to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(threadSymbol)?.kind, .class)

        let threadType = sema.types.make(.classType(ClassType(
            classSymbol: threadSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: threadSymbol), threadType)

        let threadFunctionFQName = ["kotlin", "concurrent", "thread"].map { interner.intern($0) }
        let threadFunctionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: threadFunctionFQName),
            "Expected kotlin.concurrent.thread to be registered"
        )
        let threadSignature = try XCTUnwrap(sema.symbols.functionSignature(for: threadFunctionSymbol))
        XCTAssertTrue(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: threadFunctionSymbol), "kk_thread_create")
        XCTAssertEqual(threadSignature.receiverType, nil)
        XCTAssertEqual(threadSignature.returnType, threadType)
        XCTAssertEqual(threadSignature.parameterTypes.count, 6)
        XCTAssertEqual(threadSignature.parameterTypes[0], sema.types.booleanType)
        XCTAssertEqual(threadSignature.parameterTypes[1], sema.types.booleanType)
        XCTAssertEqual(threadSignature.parameterTypes[3], sema.types.makeNullable(sema.types.stringType))
        XCTAssertEqual(threadSignature.parameterTypes[4], sema.types.intType)

        let classLoaderFQName = ["java", "lang", "ClassLoader"].map { interner.intern($0) }
        let classLoaderSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classLoaderFQName),
            "Expected java.lang.ClassLoader to be registered"
        )
        let classLoaderType = sema.types.make(.classType(ClassType(
            classSymbol: classLoaderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableClassLoaderType = sema.types.makeNullable(classLoaderType)
        XCTAssertEqual(threadSignature.parameterTypes[2], nullableClassLoaderType)

        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType
        )))
        XCTAssertEqual(threadSignature.parameterTypes[5], blockType)
        XCTAssertEqual(threadSignature.valueParameterHasDefaultValues, [true, true, true, true, true, false])
    }

    func testThreadResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.thread

        fun probe(): Unit {
            thread(
                start = false,
                isDaemon = false,
                contextClassLoader = null,
                name = "worker",
                priority = 7,
                block = {}
            )
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected thread call to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testVolatileAnnotationClassIsRegisteredWithFieldTarget() throws {
        let (sema, interner) = try makeSema()

        let volatileFQName = ["kotlin", "concurrent", "Volatile"].map { interner.intern($0) }
        let volatileSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: volatileFQName),
            "Expected kotlin.concurrent.Volatile to be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(volatileSymbol)?.kind, .annotationClass)
        XCTAssertTrue(sema.symbols.symbol(volatileSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(
            sema.symbols.annotations(for: volatileSymbol).contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.FIELD"]
            },
            "Expected Volatile to carry @Target(AnnotationTarget.FIELD)"
        )
    }

    func testVolatileAnnotationResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.Volatile

        class Holder {
            @Volatile
            var value: Int = 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Volatile annotation to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - fixedRateTimer (STDLIB-CONC-FN-004)

    func testJavaUtilTimerClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: timerFQName),
            "Expected java.util.Timer to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(timerSymbol)?.kind, .class)
    }

    func testJavaUtilTimerTaskClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: timerTaskFQName),
            "Expected java.util.TimerTask to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(timerTaskSymbol)?.kind, .class)
    }

    func testJavaUtilDateClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let dateFQName = ["java", "util", "Date"].map { interner.intern($0) }
        let dateSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: dateFQName),
            "Expected java.util.Date to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(dateSymbol)?.kind, .class)
    }

    func testFixedRateTimerWithInitialDelaySignature() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerFQName))
        let timerType = sema.types.make(.classType(ClassType(
            classSymbol: timerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerTaskFQName))
        let timerTaskType = sema.types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol,
            args: [],
            nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))

        let fixedRateTimerFQName = ["kotlin", "concurrent", "fixedRateTimer"].map { interner.intern($0) }
        let matchingSymbol = sema.symbols.lookupAll(fqName: fixedRateTimerFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 5
                && signature.parameterTypes[0] == sema.types.makeNullable(sema.types.stringType)
                && signature.parameterTypes[1] == sema.types.booleanType
                && signature.parameterTypes[2] == sema.types.longType
                && signature.parameterTypes[3] == sema.types.longType
                && signature.parameterTypes[4] == actionType
                && signature.returnType == timerType
        }
        let signature = try XCTUnwrap(
            matchingSymbol.flatMap { sema.symbols.functionSignature(for: $0) },
            "Expected fixedRateTimer(name, daemon, initialDelay, period, action) to be registered"
        )
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, true, true, false, false])
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: try XCTUnwrap(matchingSymbol)),
            "kk_fixed_rate_timer_delay"
        )
    }

    func testFixedRateTimerWithStartAtSignature() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerFQName))
        let timerType = sema.types.make(.classType(ClassType(
            classSymbol: timerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerTaskFQName))
        let timerTaskType = sema.types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol,
            args: [],
            nullability: .nonNull
        )))

        let dateFQName = ["java", "util", "Date"].map { interner.intern($0) }
        let dateSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: dateFQName))
        let dateType = sema.types.make(.classType(ClassType(
            classSymbol: dateSymbol,
            args: [],
            nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))

        let fixedRateTimerFQName = ["kotlin", "concurrent", "fixedRateTimer"].map { interner.intern($0) }
        let matchingSymbol = sema.symbols.lookupAll(fqName: fixedRateTimerFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 5
                && signature.parameterTypes[0] == sema.types.makeNullable(sema.types.stringType)
                && signature.parameterTypes[1] == sema.types.booleanType
                && signature.parameterTypes[2] == dateType
                && signature.parameterTypes[3] == sema.types.longType
                && signature.parameterTypes[4] == actionType
                && signature.returnType == timerType
        }
        let signature = try XCTUnwrap(
            matchingSymbol.flatMap { sema.symbols.functionSignature(for: $0) },
            "Expected fixedRateTimer(name, daemon, startAt, period, action) to be registered"
        )
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, true, false, false, false])
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: try XCTUnwrap(matchingSymbol)),
            "kk_fixed_rate_timer_start_at"
        )
    }

    func testFixedRateTimerWithInitialDelayResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.fixedRateTimer

        fun probe() {
            fixedRateTimer(
                name = "test",
                daemon = false,
                initialDelay = 0L,
                period = 1000L
            ) {
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected fixedRateTimer(initialDelay) call to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

}
