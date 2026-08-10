#if canImport(Testing)
/// STDLIB-NATIVE-REF-002: Sema-level tests for `kotlin.native.ref` and
/// `kotlin.native.runtime` exposure.
///
/// A single Sema pass resolves all source packages and both the opt-in diagnostic
/// checks and the package surface registration assertions are verified in the
/// same context.

@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NativeRefRuntimeSemaTests {

    @Test func testNativeRefRuntimeSema() throws {
        let sources: [String] = [
            // testUsingWeakReferenceWithoutOptInProducesDiagnostic
            """
            package sample0
                    import kotlin.native.ref.WeakReference

                    fun probe(s: String): WeakReference<String> {
                        return WeakReference(s)
                    }

            """,

            // testUsingWeakReferenceWithOptInSuppressesDiagnostic
            """
            package sample1
                    @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
                    import kotlin.native.ref.WeakReference

                    fun probe(s: String): WeakReference<String> {
                        return WeakReference(s)
                    }

            """,

            // testUsingGCWithoutNativeRuntimeApiOptInProducesDiagnostic
            """
            package sample2
                    import kotlin.native.runtime.GC

                    fun probe() {
                        GC.collect()
                    }

            """,

            // testUsingGCWithNativeRuntimeApiOptInSuppressesDiagnostic
            """
            package sample3
                    @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
                    import kotlin.native.runtime.GC

                    fun probe() {
                        GC.collect()
                    }

            """,
            // Ensure kotlin.native.ref and kotlin.native.runtime packages are loaded for surface assertions.
            """
            package sample4
                    import kotlin.native.ref.*
                    import kotlin.native.runtime.*

                    fun noop() {}
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // testUsingWeakReferenceWithoutOptInProducesDiagnostic
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let optInDiagnostics = sampleDiags.filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN"
                }
                #expect(
                    !(optInDiagnostics.isEmpty),
                    "Expected opt-in diagnostic for WeakReference usage without @OptIn"
                )
            }
            // testUsingWeakReferenceWithOptInSuppressesDiagnostic
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let optInDiagnostics = sampleDiags.filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN"
                }
                #expect(
                    optInDiagnostics.isEmpty,
                    "Expected no opt-in diagnostic when @OptIn(ExperimentalNativeApi::class) is present"
                )
            }
            // testUsingGCWithoutNativeRuntimeApiOptInProducesDiagnostic
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let optInDiagnostics = sampleDiags.filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN"
                }
                #expect(
                    !(optInDiagnostics.isEmpty),
                    "Expected opt-in diagnostic for GC usage without @OptIn(NativeRuntimeApi::class)"
                )
            }
            // testUsingGCWithNativeRuntimeApiOptInSuppressesDiagnostic
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let optInDiagnostics = sampleDiags.filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN"
                }
                #expect(
                    optInDiagnostics.isEmpty,
                    "Expected no opt-in diagnostic when @OptIn(NativeRuntimeApi::class) is present"
                )
            }


            // === testNativeRefPackageIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "ref"].map { interner.intern($0) }
                #expect(
                    sema.symbols.lookup(fqName: fqName) != nil,
                    "Expected kotlin.native.ref package to be registered"
                )
            }

            // === testNativeRuntimePackageIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "runtime"].map { interner.intern($0) }
                #expect(
                    sema.symbols.lookup(fqName: fqName) != nil,
                    "Expected kotlin.native.runtime package to be registered"
                )
            }

            // === testNativeRuntimeApiMarkerIsRegisteredAsRequiresOptIn ===

            do {
                let fqName = ["kotlin", "native", "runtime", "NativeRuntimeApi"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.runtime.NativeRuntimeApi to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)

                let annotations = sema.symbols.annotations(for: symbol)
                #expect(
                    annotations.contains {
                        $0.annotationFQName == "kotlin.RequiresOptIn"
                            && $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
                    }, "NativeRuntimeApi should carry @RequiresOptIn(ERROR), got \(annotations)"
                )
                #expect(
                    annotations.contains {
                        $0.annotationFQName == "kotlin.annotation.Target"
                            && $0.arguments.contains("AnnotationTarget.FUNCTION")
                            && $0.arguments.contains("AnnotationTarget.PROPERTY")
                            && $0.arguments.contains("AnnotationTarget.TYPEALIAS")
                    }, "NativeRuntimeApi should carry the Kotlin/Native runtime target set, got \(annotations)"
                )
            }

            // === testWeakReferenceClassIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.ref.WeakReference to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .class, "WeakReference should be a class")
            }

            // === testWeakReferenceHasTypeParameter ===

            do {
                let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
                let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
                let typeParams = sema.types.nominalTypeParameterSymbols(for: classSymbol)
                #expect(typeParams.count == 1, "WeakReference should have exactly one type parameter")
            }

            // === testWeakReferenceHasGetMember ===

            do {
                let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
                let getMemberFQName = classFQName + [interner.intern("get")]
                let members = sema.symbols.lookupAll(fqName: getMemberFQName)
                #expect(!(members.isEmpty), "WeakReference should have a get() member")

                let getMember = try #require(members.first)
                let signature = try #require(sema.symbols.functionSignature(for: getMember))
                #expect(signature.parameterTypes.count == 0, "WeakReference.get() should take no parameters")
                // Return type should be nullable (T?)
                let returnKind = sema.types.kind(of: signature.returnType)
                if case let .typeParam(param) = returnKind {
                    #expect(param.nullability == .nullable, "get() return type should be nullable T")
                } else {
                    Issue.record("Expected return type to be a nullable type param, got \(returnKind)")
                }
                #expect(
                    sema.symbols.externalLinkName(for: getMember) == "kk_weak_ref_get",
                    "WeakReference.get() should lower to kk_weak_ref_get"
                )
            }

            // === testWeakReferenceHasConstructor ===

            do {
                let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
                let ctorFQName = classFQName + [interner.intern("<init>")]
                let ctor = try #require(
                    sema.symbols.lookupAll(fqName: ctorFQName).first,
                    "WeakReference should have a constructor"
                )
                let signature = try #require(sema.symbols.functionSignature(for: ctor))
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.typeParameterSymbols.count == 1)
                #expect(signature.classTypeParameterCount == 1)
                #expect(
                    sema.symbols.externalLinkName(for: ctor) == "kk_weak_ref_create",
                    "WeakReference constructor should lower to kk_weak_ref_create"
                )
            }

            // === testWeakReferenceHasClearMember ===

            do {
                let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
                let clearMemberFQName = classFQName + [interner.intern("clear")]
                let clearMember = try #require(
                    sema.symbols.lookupAll(fqName: clearMemberFQName).first,
                    "WeakReference should have a clear() member"
                )
                let signature = try #require(sema.symbols.functionSignature(for: clearMember))
                #expect(signature.parameterTypes.count == 0)
                #expect(signature.returnType == sema.types.unitType)
                #expect(
                    sema.symbols.externalLinkName(for: clearMember) == "kk_weak_ref_clear",
                    "WeakReference.clear() should lower to kk_weak_ref_clear"
                )
            }

            // === testWeakReferenceIsTaggedExperimentalNativeApi ===

            do {
                let fqName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    hasOptInAnnotation(on: symbol, markerContaining: "ExperimentalNativeApi", sema: sema),
                    "WeakReference should carry @ExperimentalNativeApi annotation"
                )
            }

            // === testCreateCleanerFunctionIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "ref", "createCleaner"].map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: fqName)
                #expect(!(symbols.isEmpty), "Expected kotlin.native.ref.createCleaner to be registered")
            }

            // === testCreateCleanerHasTwoParameters ===

            do {
                let fqName = ["kotlin", "native", "ref", "createCleaner"].map { interner.intern($0) }
                let sym = try #require(sema.symbols.lookupAll(fqName: fqName).first)
                let signature = try #require(sema.symbols.functionSignature(for: sym))
                #expect(signature.parameterTypes.count == 2, "createCleaner should accept (value, block)")
                #expect(
                    sema.symbols.externalLinkName(for: sym) == "kk_cleaner_create",
                    "createCleaner should lower to kk_cleaner_create"
                )
            }

            // === testCreateCleanerIsTaggedExperimentalNativeApi ===

            do {
                let fqName = ["kotlin", "native", "ref", "createCleaner"].map { interner.intern($0) }
                let sym = try #require(sema.symbols.lookupAll(fqName: fqName).first)
                #expect(
                    hasOptInAnnotation(on: sym, markerContaining: "ExperimentalNativeApi", sema: sema),
                    "createCleaner should carry @ExperimentalNativeApi annotation"
                )
            }

            // === testGCObjectIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.runtime.GC to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .object, "GC should be an object")
            }

            // === testGCHasCollectMember ===

            do {
                let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
                let collectFQName = objectFQName + [interner.intern("collect")]
                let members = sema.symbols.lookupAll(fqName: collectFQName)
                #expect(!(members.isEmpty), "GC should have a collect() member")

                let member = try #require(members.first)
                let sig = try #require(sema.symbols.functionSignature(for: member))
                #expect(sig.returnType == sema.types.unitType, "GC.collect() should return Unit")
                #expect(
                    sema.symbols.externalLinkName(for: member) == "kk_gc_collect",
                    "GC.collect() should lower to kk_gc_collect"
                )
            }

            // === testGCHasScheduleMember ===

            do {
                let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
                let scheduleFQName = objectFQName + [interner.intern("schedule")]
                let members = sema.symbols.lookupAll(fqName: scheduleFQName)
                #expect(!(members.isEmpty), "GC should have a schedule() member")
                let member = try #require(members.first)
                #expect(
                    sema.symbols.externalLinkName(for: member) == "kk_gc_schedule",
                    "GC.schedule() should lower to kk_gc_schedule"
                )
            }

            // === testGCHasRuntimeTuningProperties ===

            do {
                let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
                let expected: [(name: String, type: TypeID, link: String)] = [
                    ("targetHeapBytes", sema.types.longType, "kk_gc_target_heap_bytes"),
                    ("targetHeapUtilization", sema.types.doubleType, "kk_gc_target_heap_utilization"),
                    ("maxHeapBytes", sema.types.longType, "kk_gc_max_heap_bytes"),
                ]

                for property in expected {
                    let propertyFQName = objectFQName + [interner.intern(property.name)]
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: propertyFQName),
                        "GC should have \(property.name)"
                    )
                    #expect(sema.symbols.propertyType(for: symbol) == property.type)
                    #expect(sema.symbols.externalLinkName(for: symbol) == property.link)
                }
            }

            // === testGCIsTaggedNativeRuntimeApi ===

            do {
                let fqName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
                    "GC should carry @NativeRuntimeApi annotation"
                )
            }

            // === testRootSetStatisticsClassIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "runtime", "RootSetStatistics"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.runtime.RootSetStatistics to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .class)
            }

            // === testRootSetStatisticsHasConstructorAndProperties ===

            do {
                let classFQName = ["kotlin", "native", "runtime", "RootSetStatistics"].map { interner.intern($0) }
                let expectedProperties = [
                    "threadLocalReferences",
                    "stackReferences",
                    "globalReferences",
                    "stableReferences",
                ]

                for property in expectedProperties {
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                        "RootSetStatistics should expose \(property)"
                    )
                    #expect(sema.symbols.propertyType(for: symbol) == sema.types.longType)
                }

                let ctor = try #require(
                    sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first,
                    "RootSetStatistics should expose its primary constructor"
                )
                let signature = try #require(sema.symbols.functionSignature(for: ctor))
                #expect(
                    signature.parameterTypes
                        == Array(repeating: sema.types.longType, count: expectedProperties.count)
                )
            }

            // === testRootSetStatisticsIsTaggedNativeRuntimeApi ===

            do {
                let fqName = ["kotlin", "native", "runtime", "RootSetStatistics"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
                    "RootSetStatistics should carry @NativeRuntimeApi annotation"
                )
            }

            // === testSweepStatisticsClassIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "runtime", "SweepStatistics"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.runtime.SweepStatistics to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .class)
            }

            // === testSweepStatisticsHasConstructorAndProperties ===

            do {
                let classFQName = ["kotlin", "native", "runtime", "SweepStatistics"].map { interner.intern($0) }
                let expectedProperties = [
                    "sweptCount",
                    "keptCount",
                ]

                for property in expectedProperties {
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                        "SweepStatistics should expose \(property)"
                    )
                    #expect(sema.symbols.propertyType(for: symbol) == sema.types.longType)
                }

                let ctor = try #require(
                    sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first,
                    "SweepStatistics should expose its primary constructor"
                )
                let signature = try #require(sema.symbols.functionSignature(for: ctor))
                #expect(
                    signature.parameterTypes
                        == Array(repeating: sema.types.longType, count: expectedProperties.count)
                )
            }

            // === testSweepStatisticsIsTaggedNativeRuntimeApi ===

            do {
                let fqName = ["kotlin", "native", "runtime", "SweepStatistics"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
                    "SweepStatistics should carry @NativeRuntimeApi annotation"
                )
            }

            // === testGCInfoClassIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.runtime.GCInfo to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .class)
            }

            // === testGCInfoConstructorMatchesKotlinNativeSurface ===

            do {
                let classFQName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
                let ctorFQName = classFQName + [interner.intern("<init>")]
                let ctor = try #require(
                    sema.symbols.lookupAll(fqName: ctorFQName).first,
                    "GCInfo should expose its primary constructor"
                )
                let signature = try #require(sema.symbols.functionSignature(for: ctor))
                #expect(signature.parameterTypes.count == 15)
                #expect(
                    signature.parameterTypes[0] == sema.types.longType,
                    "GCInfo.epoch constructor parameter should be Long"
                )
                let rootSetSymbol = try #require(
                    sema.symbols.lookup(fqName: classFQName + [interner.intern("rootSet")])
                )
                let rootSetType = try #require(sema.symbols.propertyType(for: rootSetSymbol))
                #expect(signature.parameterTypes[10] == rootSetType)
                let sweepStatisticsSymbol = try #require(
                    sema.symbols.lookup(fqName: classFQName + [interner.intern("sweepStatistics")])
                )
                let sweepStatisticsType = try #require(
                    sema.symbols.propertyType(for: sweepStatisticsSymbol)
                )
                #expect(signature.parameterTypes[12] == sweepStatisticsType)
            }

            // === testGCInfoHasTimingProperties ===

            do {
                let classFQName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
                let longProperties = [
                    "epoch",
                    "startTimeNs",
                    "endTimeNs",
                    "firstPauseRequestTimeNs",
                    "firstPauseStartTimeNs",
                    "firstPauseEndTimeNs",
                ]
                for property in longProperties {
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                        "GCInfo should expose \(property)"
                    )
                    #expect(sema.symbols.propertyType(for: symbol) == sema.types.longType)
                }

                let nullableLongProperties = [
                    "secondPauseRequestTimeNs",
                    "secondPauseStartTimeNs",
                    "secondPauseEndTimeNs",
                    "postGcCleanupTimeNs",
                ]
                for property in nullableLongProperties {
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                        "GCInfo should expose \(property)"
                    )
                    let type = try #require(sema.symbols.propertyType(for: symbol))
                    #expect(sema.types.nullability(of: type) == .nullable)
                    #expect(sema.types.makeNonNullable(type) == sema.types.longType)
                }
            }

            // === testGCInfoHasSummaryProperties ===

            do {
                let classFQName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }

                let rootSetSymbol = try #require(
                    sema.symbols.lookup(fqName: classFQName + [interner.intern("rootSet")])
                )
                let rootSetType = try #require(sema.symbols.propertyType(for: rootSetSymbol))
                #expect(
                    try className(for: rootSetType, sema: sema, interner: interner) == "RootSetStatistics"
                )

                let markedCountSymbol = try #require(
                    sema.symbols.lookup(fqName: classFQName + [interner.intern("markedCount")])
                )
                #expect(sema.symbols.propertyType(for: markedCountSymbol) == sema.types.longType)

                let sweepStatisticsSymbol = try #require(
                    sema.symbols.lookup(fqName: classFQName + [interner.intern("sweepStatistics")])
                )
                let sweepStatisticsType = try #require(
                    sema.symbols.propertyType(for: sweepStatisticsSymbol)
                )
                let sweepStatisticsClassName = try mapValueClassName(
                    for: sweepStatisticsType,
                    sema: sema,
                    interner: interner
                )
                #expect(sweepStatisticsClassName == "SweepStatistics")

                for property in ["memoryUsageBefore", "memoryUsageAfter"] {
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: classFQName + [interner.intern(property)])
                    )
                    let propertyType = try #require(sema.symbols.propertyType(for: symbol))
                    let valueClassName = try mapValueClassName(
                        for: propertyType,
                        sema: sema,
                        interner: interner
                    )
                    #expect(valueClassName == "MemoryUsage")
                }
            }

            // === testMemoryUsageSurfaceForGCInfoIsRegistered ===

            do {
                let classFQName = ["kotlin", "native", "runtime", "MemoryUsage"].map { interner.intern($0) }
                let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
                #expect(sema.symbols.symbol(classSymbol)?.kind == .class)
                #expect(
                    hasOptInAnnotation(on: classSymbol, markerContaining: "NativeRuntimeApi", sema: sema),
                    "MemoryUsage should carry @NativeRuntimeApi annotation"
                )

                let propertySymbol = try #require(
                    sema.symbols.lookup(fqName: classFQName + [interner.intern("totalObjectsSizeBytes")])
                )
                #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.longType)

                let ctor = try #require(
                    sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first
                )
                let signature = try #require(sema.symbols.functionSignature(for: ctor))
                #expect(signature.parameterTypes == [sema.types.longType])
            }

            // === testGCInfoIsTaggedNativeRuntimeApi ===

            do {
                let fqName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
                    "GCInfo should carry @NativeRuntimeApi annotation"
                )
            }

            // === testDebuggingObjectIsRegistered ===

            do {
                let fqName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.native.runtime.Debugging to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .object, "Debugging should be an object")
            }

            // === testDebuggingHasIsThreadStateRunnableProperty ===

            do {
                let objectFQName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
                let propFQName = objectFQName + [interner.intern("isThreadStateRunnable")]
                let sym = try #require(
                    sema.symbols.lookup(fqName: propFQName),
                    "Debugging should expose isThreadStateRunnable property"
                )
                #expect(
                    sema.symbols.propertyType(for: sym) == sema.types.booleanType,
                    "isThreadStateRunnable should be Boolean"
                )
                #expect(sema.symbols.externalLinkName(for: sym) == "kk_debugging_is_thread_state_runnable")
            }

            // === testDebuggingHasTrackingProperties ===

            do {
                let objectFQName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
                let expected: [(name: String, link: String)] = [
                    ("gcSuspendCount", "kk_debugging_gc_suspend_count"),
                    ("threadCount", "kk_debugging_thread_count"),
                    ("globalObjectCount", "kk_debugging_global_object_count"),
                ]

                for property in expected {
                    let propFQName = objectFQName + [interner.intern(property.name)]
                    let sym = try #require(
                        sema.symbols.lookup(fqName: propFQName),
                        "Debugging should expose \(property.name) property"
                    )
                    #expect(
                        sema.symbols.propertyType(for: sym) == sema.types.intType,
                        "\(property.name) should be Int"
                    )
                    #expect(sema.symbols.externalLinkName(for: sym) == property.link)
                }
            }

            // === testDebuggingIsTaggedNativeRuntimeApi ===

            do {
                let fqName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                #expect(
                    hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
                    "Debugging should carry @NativeRuntimeApi annotation"
                )
            }
        }
    }

    // MARK: - Shared helpers

    private func hasOptInAnnotation(
        on symbol: SymbolID,
        markerContaining keyword: String,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains {
            $0.annotationFQName.lowercased().contains(keyword.lowercased())
        }
    }

    private func className(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> String {
        let typeKind = sema.types.kind(of: type)
        let classType = try requireTestValue(
            { () -> ClassType? in
                guard case let .classType(classType) = typeKind else { return nil }
                return classType
            }(),
            "Expected class type, got \(typeKind)"
        )
        let symbol = try #require(sema.symbols.symbol(classType.classSymbol))
        return interner.resolve(symbol.name)
    }

    private func mapValueClassName(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> String {
        let typeKind = sema.types.kind(of: type)
        let mapType = try requireTestValue(
            { () -> ClassType? in
                guard case let .classType(mapType) = typeKind else { return nil }
                return mapType
            }(),
            "Expected Map class type, got \(typeKind)"
        )
        let mapSymbol = try #require(sema.symbols.symbol(mapType.classSymbol))
        #expect(interner.resolve(mapSymbol.name) == "Map")
        let valueType = try requireTestValue(
            { () -> TypeID? in
                guard mapType.args.count >= 2,
                      case let .out(valueType) = mapType.args[1]
                else {
                    return nil
                }
                return valueType
            }(),
            "Expected Map<String, V> value projection"
        )
        return try className(for: valueType, sema: sema, interner: interner)
    }


}
#endif
