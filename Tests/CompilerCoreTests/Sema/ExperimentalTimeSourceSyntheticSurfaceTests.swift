#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExperimentalTimeSourceSyntheticSurfaceTests {
    @Test
    func testExperimentalTimeSourceSyntheticSurfaceSema() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
            """
            package sample1
            import kotlin.time.ExperimentalTime

            @ExperimentalTime
            fun experimentalThing1(): Int = 1
            """,
            """
            package sample2
            import kotlin.time.ExperimentalTime

            @ExperimentalTime
            fun experimentalThing2(): Int = 1

            fun useIt2(): Int = experimentalThing2()
            """,
            """
            package sample3
            import kotlin.time.ExperimentalTime

            @ExperimentalTime
            fun experimentalThing3(): Int = 1

            @OptIn(ExperimentalTime::class)
            fun useIt3(): Int = experimentalThing3()
            """,
            """
            package sample4
            import kotlin.time.AbstractDoubleTimeSource
            import kotlin.time.DurationUnit
            import kotlin.time.ExperimentalTime

            @OptIn(ExperimentalTime::class)
            class ProbeDoubleSource : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
                protected override fun read(): Double = 12.5
            }

            @OptIn(ExperimentalTime::class)
            fun markDouble(source: ProbeDoubleSource) = source.markNow()
            """,
            """
            package sample5
            import kotlin.time.AbstractLongTimeSource
            import kotlin.time.DurationUnit
            import kotlin.time.ExperimentalTime

            @OptIn(ExperimentalTime::class)
            class ProbeLongSource : AbstractLongTimeSource(DurationUnit.NANOSECONDS) {
                protected override fun read(): Long = 42L
            }

            @OptIn(ExperimentalTime::class)
            fun markLong(source: ProbeLongSource) = source.markNow()
            """,
            """
            package sample6
            import kotlin.time.Duration.Companion.milliseconds
            import kotlin.time.ComparableTimeMark
            import kotlin.time.ExperimentalTime
            import kotlin.time.TestTimeSource

            @OptIn(ExperimentalTime::class)
            fun markTestTime(): ComparableTimeMark {
                val source = TestTimeSource()
                source += 5.milliseconds
                return source.markNow()
            }
            """,
            """
            package sample7
            import kotlin.time.*

            fun makeClock(source: TimeSource, origin: Instant): Clock {
                return source.asClock(origin)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            func diagnosticsForPath(_ path: String) -> [Diagnostic] {
                guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
                return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
            }

            // testExperimentalTimeIsRequiresOptInMarker
            do {
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

            // testExperimentalTimeCarriesOfficialTargets
            do {
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

            // testExperimentalTimeIsApplicableToFunction
            do {
                let samplePath = paths[1]
                let targetDiagnostics = diagnosticsForPath(samplePath).filter {
                    $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
                }
                #expect(
                    targetDiagnostics.isEmpty,
                    "Expected @ExperimentalTime to be applicable to a function, got \(ctx.diagnostics.diagnostics)"
                )
            }

            // testExperimentalTimeUseRequiresOptIn
            do {
                let samplePath = paths[2]
                let diagnostics = diagnosticsForPath(samplePath).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
                let hasOptInError = diagnostics.contains {
                    $0.severity == .error && $0.message.contains("kotlin.time.ExperimentalTime")
                }
                #expect(
                    hasOptInError,
                    "Expected @ExperimentalTime usage to require opt-in, got \(ctx.diagnostics.diagnostics)"
                )
            }

            // testExperimentalTimeAcceptsExplicitOptIn
            do {
                let samplePath = paths[3]
                let diagnostics = diagnosticsForPath(samplePath).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
                #expect(
                    diagnostics.isEmpty,
                    "Expected @OptIn(ExperimentalTime::class) to suppress opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
                )
            }

            // testAbstractDoubleTimeSourceSurfaceIsRegistered
            do {
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
                #expect(sema.symbols.directSupertypes(for: abstractDoubleSymbol) == [withComparableMarksSymbol])

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

            // testAbstractDoubleTimeSourceCanBeSubclassedInSource
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath)
                #expect(
                    sampleDiags.isEmpty,
                    "AbstractDoubleTimeSource subclass source must compile cleanly, got: \(sampleDiags)"
                )

                let markSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample4"),
                    interner.intern("markDouble"),
                ]))
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

            // testAbstractLongTimeSourceSurfaceIsRegistered
            do {
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
                #expect(sema.symbols.directSupertypes(for: abstractLongSymbol) == [withComparableMarksSymbol])

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

            // testAbstractLongTimeSourceCanBeSubclassedInSource
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath)
                #expect(
                    sampleDiags.isEmpty,
                    "AbstractLongTimeSource subclass source must compile cleanly, got: \(sampleDiags)"
                )

                let markSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample5"),
                    interner.intern("markLong"),
                ]))
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

            // testTestTimeSourceSurfaceIsRegistered
            do {
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
                ]).first)
                let readSignature = try #require(sema.symbols.functionSignature(for: readSymbol))
                let readInfo = try #require(sema.symbols.symbol(readSymbol))
                #expect(readInfo.visibility == .protected)
                #expect(readInfo.flags.isSuperset(of: [.openType, .overrideMember]))
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

            // testTestTimeSourceResolvesOperatorAndInheritedMarkNowInSource
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath)
                #expect(
                    sampleDiags.isEmpty,
                    "TestTimeSource source must compile cleanly, got: \(sampleDiags)"
                )

                let markSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample6"),
                    interner.intern("markTestTime"),
                ]))
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

            // testTimeSourceAsClockExtensionIsRegistered
            do {
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
                #expect(sema.symbols.externalLinkName(for: asClockSymbol) == "kk_time_source_as_clock")
                #expect(signature.receiverType == timeSourceType)
                #expect(signature.parameterTypes == [instantType])
                #expect(signature.returnType == clockType)
            }

            // testTimeSourceAsClockResolvesInSource
            do {
                let samplePath = paths[7]
                let sampleDiags = diagnosticsForPath(samplePath)
                #expect(
                    sampleDiags.isEmpty,
                    "TimeSource.asClock source must compile cleanly, got: \(sampleDiags)"
                )

                let makeClockSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample7"),
                    interner.intern("makeClock"),
                ]))
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
    }
}
#endif
