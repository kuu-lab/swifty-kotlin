#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExperimentalTimeSourceSyntheticSurfaceTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private static let timeSourceSource: String = """
    import kotlin.time.AbstractDoubleTimeSource
    import kotlin.time.AbstractLongTimeSource
    import kotlin.time.Clock
    import kotlin.time.ComparableTimeMark
    import kotlin.time.Duration.Companion.milliseconds
    import kotlin.time.DurationUnit
    import kotlin.time.ExperimentalTime
    import kotlin.time.Instant
    import kotlin.time.TestTimeSource
    import kotlin.time.TimeSource

    @OptIn(ExperimentalTime::class)
    class ProbeDoubleSource : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
        protected override fun read(): Double = 12.5
    }

    @OptIn(ExperimentalTime::class)
    fun markDouble(source: ProbeDoubleSource) = source.markNow()

    @OptIn(ExperimentalTime::class)
    class ProbeLongSource : AbstractLongTimeSource(DurationUnit.NANOSECONDS) {
        protected override fun read(): Long = 42L
    }

    @OptIn(ExperimentalTime::class)
    fun markLong(source: ProbeLongSource) = source.markNow()

    @OptIn(ExperimentalTime::class)
    fun markTest(): ComparableTimeMark {
        val source = TestTimeSource()
        source += 5.milliseconds
        return source.markNow()
    }

    fun makeClock(source: TimeSource, origin: Instant): Clock {
        return source.asClock(origin)
    }
    """

    private static nonisolated(unsafe) var _sharedSourceSema: (SemaModule, StringInterner)?

    private func sharedSourceSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSourceSema { return cached }
        let pair = try makeSema(source: Self.timeSourceSource)
        Self._sharedSourceSema = pair
        return pair
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected experimental time source surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test; an opt-in error throws out of sema.
        }
        return ctx
    }

    @Test func testExperimentalTimeIsRequiresOptInMarker() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let experimentalTimeSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("ExperimentalTime"),
        ]))
        #expect(sema.symbols.symbol(experimentalTimeSymbol)?.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: experimentalTimeSymbol)
        let hasRequiresOptIn = annotations.contains {
            $0.annotationFQName == "kotlin.RequiresOptIn"
                && $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
        }
        #expect(
            hasRequiresOptIn,
            "ExperimentalTime should be an ERROR-level opt-in marker, got: \(annotations)"
        )
        let hasBinaryRetention = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments.contains("AnnotationRetention.BINARY")
        }
        #expect(
            hasBinaryRetention,
            "ExperimentalTime should use binary retention, got: \(annotations)"
        )
    }

    @Test func testExperimentalTimeCarriesOfficialTargets() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let experimentalTimeSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("ExperimentalTime"),
        ]))

        let annotations = sema.symbols.annotations(for: experimentalTimeSymbol)
        let hasTarget = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Target"
                && $0.arguments == [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
        }
        #expect(
            hasTarget,
            "ExperimentalTime must carry the official @Target list, got \(annotations)"
        )
    }

    @Test func testExperimentalTimeImplicitConstructorIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let experimentalTimeSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("ExperimentalTime"),
        ]))
        let experimentalTimeType = sema.types.make(.classType(ClassType(
            classSymbol: experimentalTimeSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorSymbol = try #require(sema.symbols.lookupAll(
            fqName: kotlinTime + [interner.intern("ExperimentalTime"), interner.intern("<init>")]
        ).first { symbolID in
            guard sema.symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == experimentalTimeType
                && signature.parameterTypes.isEmpty
                && signature.returnType == experimentalTimeType
        })
        let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
        #expect(constructorInfo.visibility == .public)
        #expect(constructorInfo.flags.contains(.synthetic))
    }

    @Test func testExperimentalTimeIsApplicableToFunction() {
        // Regression: ExperimentalTime previously only allowed @Target(ANNOTATION_CLASS),
        // which wrongly rejected the propagating opt-in form `@ExperimentalTime fun ...`.
        let source = """
        import kotlin.time.ExperimentalTime

        @ExperimentalTime
        fun experimentalThing(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let targetDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        #expect(
            targetDiagnostics.isEmpty,
            "Expected @ExperimentalTime to be applicable to a function, got \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testExperimentalTimeUseRequiresOptIn() {
        let source = """
        import kotlin.time.ExperimentalTime

        @ExperimentalTime
        fun experimentalThing(): Int = 1

        fun useIt(): Int = experimentalThing()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        let hasOptInError = diagnostics.contains {
            $0.severity == .error && $0.message.contains("kotlin.time.ExperimentalTime")
        }
        #expect(
            hasOptInError,
            "Expected @ExperimentalTime usage to require opt-in, got \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testExperimentalTimeAcceptsExplicitOptIn() {
        let source = """
        import kotlin.time.ExperimentalTime

        @ExperimentalTime
        fun experimentalThing(): Int = 1

        @OptIn(ExperimentalTime::class)
        fun useIt(): Int = experimentalThing()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(
            diagnostics.isEmpty,
            "Expected @OptIn(ExperimentalTime::class) to suppress opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testAbstractDoubleTimeSourceSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let timeSourceSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [interner.intern("TimeSource")]))
        #expect(sema.symbols.symbol(timeSourceSymbol)?.kind == .interface)

        let withComparableMarksSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("WithComparableMarks"),
        ]))
        #expect(sema.symbols.symbol(withComparableMarksSymbol)?.kind == .interface)
        #expect(sema.symbols.parentSymbol(for: withComparableMarksSymbol) == timeSourceSymbol)
        #expect(sema.symbols.directSupertypes(for: withComparableMarksSymbol) == [timeSourceSymbol])

        let abstractDoubleSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractDoubleTimeSource"),
        ]))
        #expect(sema.symbols.symbol(abstractDoubleSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(abstractDoubleSymbol)?.flags.contains(.abstractType) == true)
        let abstractDoubleSupertypes = sema.symbols.directSupertypes(for: abstractDoubleSymbol)
        #expect(abstractDoubleSupertypes.contains(withComparableMarksSymbol))

        let durationUnitSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("DurationUnit"),
        ]))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let abstractDoubleType = sema.types.make(.classType(ClassType(
            classSymbol: abstractDoubleSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorSymbol = try #require(sema.symbols.lookupAll(
            fqName: kotlinTime + [interner.intern("AbstractDoubleTimeSource"), interner.intern("<init>")]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(constructorSignature.receiverType == abstractDoubleType)
        #expect(constructorSignature.parameterTypes == [durationUnitType])
        #expect(constructorSignature.returnType == abstractDoubleType)

        let unitSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractDoubleTimeSource"),
            interner.intern("unit"),
        ]))
        #expect(sema.symbols.symbol(unitSymbol)?.visibility == .protected)
        #expect(sema.symbols.propertyType(for: unitSymbol) == durationUnitType)

        let readSymbol = try #require(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("AbstractDoubleTimeSource"),
            interner.intern("read"),
        ]).first)
        let readSignature = try #require(sema.symbols.functionSignature(for: readSymbol))
        #expect(sema.symbols.symbol(readSymbol)?.visibility == .protected)
        #expect(sema.symbols.symbol(readSymbol)?.flags.contains(.abstractType) == true)
        #expect(readSignature.receiverType == abstractDoubleType)
        #expect(readSignature.parameterTypes == [])
        #expect(readSignature.returnType == sema.types.doubleType)
    }

    @Test func testAbstractDoubleTimeSourceCanBeSubclassedInSource() throws {
        let (sema, interner) = try sharedSourceSema()
        let markSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("markDouble")]))
        let markSignature = try #require(sema.symbols.functionSignature(for: markSymbol))
        let comparableTimeMarkSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("ComparableTimeMark"),
        ]))
        let comparableTimeMarkType = sema.types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(markSignature.returnType == comparableTimeMarkType)
    }

    @Test func testAbstractLongTimeSourceSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let withComparableMarksSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("WithComparableMarks"),
        ]))
        let abstractLongSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
        ]))
        #expect(sema.symbols.symbol(abstractLongSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(abstractLongSymbol)?.flags.contains(.abstractType) == true)
        let abstractLongSupertypes = sema.symbols.directSupertypes(for: abstractLongSymbol)
        #expect(abstractLongSupertypes.contains(withComparableMarksSymbol))

        let durationUnitSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("DurationUnit"),
        ]))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let abstractLongType = sema.types.make(.classType(ClassType(
            classSymbol: abstractLongSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorSymbol = try #require(sema.symbols.lookupAll(
            fqName: kotlinTime + [interner.intern("AbstractLongTimeSource"), interner.intern("<init>")]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(constructorSignature.receiverType == abstractLongType)
        #expect(constructorSignature.parameterTypes == [durationUnitType])
        #expect(constructorSignature.returnType == abstractLongType)

        let unitSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
            interner.intern("unit"),
        ]))
        #expect(sema.symbols.symbol(unitSymbol)?.visibility == .protected)
        #expect(sema.symbols.propertyType(for: unitSymbol) == durationUnitType)

        let readSymbol = try #require(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
            interner.intern("read"),
        ]).first)
        let readSignature = try #require(sema.symbols.functionSignature(for: readSymbol))
        #expect(sema.symbols.symbol(readSymbol)?.visibility == .protected)
        #expect(sema.symbols.symbol(readSymbol)?.flags.contains(.abstractType) == true)
        #expect(readSignature.receiverType == abstractLongType)
        #expect(readSignature.parameterTypes == [])
        #expect(readSignature.returnType == sema.types.longType)
    }

    @Test func testAbstractLongTimeSourceCanBeSubclassedInSource() throws {
        let (sema, interner) = try sharedSourceSema()
        let markSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("markLong")]))
        let markSignature = try #require(sema.symbols.functionSignature(for: markSymbol))
        let comparableTimeMarkSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("ComparableTimeMark"),
        ]))
        let comparableTimeMarkType = sema.types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(markSignature.returnType == comparableTimeMarkType)
    }

    @Test func testTestTimeSourceSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let abstractLongSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
        ]))
        let testTimeSourceSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TestTimeSource"),
        ]))
        #expect(sema.symbols.symbol(testTimeSourceSymbol)?.kind == .class)
        #expect(sema.symbols.directSupertypes(for: testTimeSourceSymbol) == [abstractLongSymbol])

        let durationSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("Duration"),
        ]))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let testTimeSourceType = sema.types.make(.classType(ClassType(
            classSymbol: testTimeSourceSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorSymbol = try #require(sema.symbols.lookupAll(
            fqName: kotlinTime + [interner.intern("TestTimeSource"), interner.intern("<init>")]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(constructorSignature.receiverType == testTimeSourceType)
        #expect(constructorSignature.parameterTypes == [])
        #expect(constructorSignature.returnType == testTimeSourceType)

        let readSymbol = try #require(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("TestTimeSource"),
            interner.intern("read"),
        ]).first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == testTimeSourceType
        })
        let readSignature = try #require(sema.symbols.functionSignature(for: readSymbol))
        let readInfo = try #require(sema.symbols.symbol(readSymbol))
        #expect(readInfo.visibility == .public)
        #expect(readInfo.flags.contains(.overrideMember))
        #expect(readSignature.receiverType == testTimeSourceType)
        #expect(readSignature.parameterTypes == [])
        #expect(readSignature.returnType == sema.types.longType)

        let plusAssignSymbol = try #require(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("TestTimeSource"),
            interner.intern("plusAssign"),
        ]).first)
        let plusAssignSignature = try #require(sema.symbols.functionSignature(for: plusAssignSymbol))
        let plusAssignInfo = try #require(sema.symbols.symbol(plusAssignSymbol))
        #expect(plusAssignInfo.flags.contains(.operatorFunction))
        #expect(plusAssignSignature.receiverType == testTimeSourceType)
        #expect(plusAssignSignature.parameterTypes == [durationType])
        #expect(plusAssignSignature.returnType == sema.types.unitType)
    }

    @Test func testTestTimeSourceResolvesOperatorAndInheritedMarkNowInSource() throws {
        let (sema, interner) = try sharedSourceSema()
        let markSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("markTest")]))
        let markSignature = try #require(sema.symbols.functionSignature(for: markSymbol))
        let comparableTimeMarkSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("ComparableTimeMark"),
        ]))
        let comparableTimeMarkType = sema.types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(markSignature.returnType == comparableTimeMarkType)
    }

    @Test func testTimeSourceAsClockExtensionIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }

        let timeSourceSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
        ]))
        let instantSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("Instant"),
        ]))
        let clockSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("Clock"),
        ]))
        #expect(
            sema.symbols.symbol(clockSymbol)?.kind == .interface,
            "Clock must remain a user-implementable interface"
        )
        let timeSourceType = sema.types.make(.classType(ClassType(
            classSymbol: timeSourceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let clockType = sema.types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))

        let asClockSymbol = try #require(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("asClock"),
        ]).first)
        let signature = try #require(sema.symbols.functionSignature(for: asClockSymbol))
        #expect(sema.symbols.externalLinkName(for: asClockSymbol) == "__kk_time_source_as_clock")
        #expect(signature.receiverType == timeSourceType)
        #expect(signature.parameterTypes == [instantType])
        #expect(signature.returnType == clockType)

        let nowSymbol = try #require(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("Clock"),
            interner.intern("now"),
        ]).first { symbol in
            guard let nowSignature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return nowSignature.receiverType == clockType
                && nowSignature.parameterTypes.isEmpty
                && nowSignature.returnType == instantType
        })
        #expect(sema.symbols.externalLinkName(for: nowSymbol) == "kk_clock_now")
    }

    @Test func testTimeSourceAsClockResolvesInSource() throws {
        let (sema, interner) = try sharedSourceSema()
        let makeClockSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("makeClock")]))
        let signature = try #require(sema.symbols.functionSignature(for: makeClockSymbol))
        let clockSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("Clock"),
        ]))
        let clockType = sema.types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(signature.returnType == clockType)
    }
}
#endif
