#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private final class JVMOwnStdlibCache: @unchecked Sendable {
    static let shared = JVMOwnStdlibCache()
    private let lock = NSLock()
    private var artifact: URL?
    func library() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        if let artifact { return artifact }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kswiftk-own-jvm-stdlib-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("kswiftk-stdlib.jar")
        let options = CompilerOptions(moduleName: "OwnStdlib", inputs: [], outputPath: output.path, emit: .jvmJar, target: .hostDefault(), stdlibOnly: true)
        let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
        try #require(result.exitCode == 0, "\(result.diagnostics.map(\.message))")
        artifact = output
        return output
    }
}

extension JVMBackendTests {
    private static let ownStdlibCases = [
        "callableReferenceCallByExtensionContracts",
        "reifiedCapturedCollectionChecks",
        "arrayConstructorInlineAndReifiedContracts",
        "collectionMutableTypeChecksAndRegexGroups",
        "reflectionOverloadedDefaultsAndInheritedContracts",
        "sequenceIndependentIterators",
        "sequenceDropWhileConsumption",
        "sequenceRuntimeBoundaries",
        "reflectionMappedTypes",
        "reflectionInvocationFailures",
        "unsignedFloatingPointBoundaries",
        "m10ClassDelegationAndOverrides",
        "m10DelegatedPropertiesAndProvideDelegate",
        "m10LazyInitializationAndRetry",
        "m10LateinitFieldsLocalsAndInitializationQuery",
        "m10GenericClassDelegationAndPropertyOperators",
        "m10StandardDelegatesAndInitializationOrder",
        "m10PrivateFieldsDelegateOrderAndMutableTokens",
        "m10MemberExtensionDelegationAndNamedFactories",
        "m10ProvideDelegateReturningLazyReceivesPropertyToken",
        "m10DelegatedInvokeAndLazyInterfaceBridges",
        "m11ValueClassesBoxingDispatchAndDefaults",
        "m11ReferenceAndWideValueClasses",
        "m11AliasesAndCallableReflection",
        "m11AnnotationConstantsAndReflection",
        "m11LoweredCallableSignaturesAndClassInitialization",
        "m11PropertyAnnotationsAndVarargs",
        "m12GenericValueClassesAndBounds",
        "m12RepeatableAnnotationsAndReflection",
        "m12ExplicitRepeatableContainer",
        "m13ArrayValueClasses",
        "m13NestedValueClasses",
        "m13ValueConstructorsDefaultsAndInitialization",
        "m13WideGenericAndMultipleMaskConstructors",
        "m14InlineValueClassesAndNonLocalReturns",
        "m14SuspendValueClassesDefaultsAndDispatch",
        "m14ReferenceSuspendResultsAndDelayedResume",
        "m14SuspendReferenceInterfacesAndValueMembers",
        "m15ReifiedOperationsAndForwarding",
        "m15InlineSuspendResumesAndReifies",
        "m15EscapingReifiedClosures",
        "m16ReifiedReferencesSpecializeAndEscape",
        "m16AnonymousObjectsCaptureRuntimeTypes",
        "m16SuspendReferencesAndObjectsResumeWithTypeCaptures",
        "m16GenericCaptureLayoutAndNestedObjects",
        "m16AdaptedReferencesAndSuspendValueResults",
        "m16SAMDefaultTokensAndReferenceEquality",
        "m17SignedNarrowTypesAndUnicode",
        "m17UnsignedArithmeticConversionsAndBits",
        "m17UnsignedArraysBoxingGenericsAndCapture",
        "m17SuspendInlineAndValueClassCarriers",
        "m17NarrowAnnotationConstants",
        "m17NullableArrayTransportAndUnsignedConstructors",
        "m18ConcatenationTemplatesAndEvaluationOrder",
        "m18TextOperationsUnicodeAndDefaults",
        "m18StringNumericConversionsAndFailures",
        "m18StringMutationTemplatesCaptureAndEscapes",
        "m18TemplatesPreserveSuspensionAndReifiedCaptures",
        "m19BuilderAndInlineText",
        "m19RegexAndSequences",
        "m19MutableSequencesAndHigherOrderVariants",
        "m19BuilderRangesDefaultsAndExceptions",
        "m19RegexBoundariesAndCallbacks",
        "m19InlineCallbacksSuspendAndFinally",
        "m20PairsGroupingAssociationsAndZip",
        "m20LazySequencesAndTerminals",
        "m20ArraysTextAndBoxedValues",
        "m20SequenceEvaluationOrderAndBounds",
        "m20InlineControlFlowSuspensionAndCapture",
        "m21BuildersYieldAllAndLazyIteration",
        "m21ControlFlowFinallyAndFailure",
        "m21CaptureGenericHelpersAndReceiverFunctions",
        "m21RestrictedReceiverTypesAndFunctionValues",
        "m21UserFunctionsShadowBuilderNames",
        "classesConstructorsPropertiesAndDynamicDispatch",
        "initializationOrderCustomAccessorsAndConstructorChains",
        "abstractClassesCovariantBridgesAndInterfaceSuper",
        "nullLiteralComparisonDoesNotCallUserEquals",
        "genericClassesAndFunctionsExecute",
        "primitiveAndReferenceArraysExecute",
        "collectionsAndIterationExecute",
        "exceptionsCatchFinallyAndEscapingControlFlow",
        "genericInterfaceBridgesAndBounds",
        "finallyLexicalScopesOverridesAndPendingConstructors",
        "lambdasClosuresHigherOrderAndSharedMutation",
        "extensionFunctionsReceiverLambdasAndNestedReceivers",
        "collectionHigherOrderOperationsAndArrayInitializers",
        "closuresInMembersInterfacesAndConstructorArguments",
        "lambdaLocalReturnsAndExceptionsPreserveCapturedCells",
        "closuresPreserveLexicalBindingsAndCallableCaptures",
        "suspendMainFunctionsReceiverLambdasAndGenericBridges",
        "suspensionResumesLocalsLoopsAndExceptionHandlers",
        "suspendSAMAndSynchronousSafeContinuation",
        "samConstructorsConversionsGenericsAndDefaultMethods",
        "inlineFunctionsExpandCallbacksAndNonLocalReturns",
        "singletonAndEnumInitializationFailuresAreCachedByJVM",
        "objectsInheritClassesAndInterfaces",
        "objectsCompanionsInitializationAndPrivateAccess",
        "dataClassesComponentsCopyEqualityAndFormatting",
        "enumsEntriesValuesAndConstantBodies",
        "sealedClassesNestedDataAndExhaustiveWhen",
        "m9NamedAndDefaultArgumentsPreserveEvaluationOrder",
        "m9InheritedInterfaceAndInlineDefaults",
        "m9InnerInstancesAndNestedOuterChains",
        "m9AnonymousObjectsCaptureAndInitializePerInstance",
        "m9DataObjectsAndDataConstructorDefaults",
        "m9CapturesExistDuringBaseInitializationAndAnonymousDefaults",
        "m9ObjectEnumSuperDefaultsAndExplicitNoarg",
        "m9MultipleMasksWideValuesAndThrowingDefaults",
        "m9GenericAnonymousAndInnerClasses",
        "m9SuspendDefaultCallsUseContinuationBeforeMasks",
        "m9NamedArrayAndHigherOrderArguments",
    ]

    @Test(arguments: Self.ownStdlibCases, [EmitMode.jvmClass, .jvmJar])
    func repositoryStdlibRuntimeRegression(name: String, mode: EmitMode) throws {
        let library = try JVMOwnStdlibCache.shared.library()
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let package = source.components(separatedBy: "\n").first(where: { $0.hasPrefix("package ") }).map { $0.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines) + "." } ?? ""
            let result = try java(["-cp", app.0.path + ":" + library.path, package + "HelloKt"])
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }
    @Test(arguments: [false, true])
    func officialKotlinConsumerUsesOnlyRepositoryStdlib(withoutOfficialCompileClasspath: Bool) throws {
        let library = try JVMOwnStdlibCache.shared.library()
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlibInterop")
        let expected = try String(contentsOf: fixtures.appendingPathComponent("consumer.out"), encoding: .utf8)
        try withWorkspace { root in
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent("consumer.kt"), to: root.appendingPathComponent("consumer.kt"))
            let arguments = withoutOfficialCompileClasspath ? ["-no-stdlib", "-no-reflect", "-cp", library.path] : []
            _ = try jvmTool("kotlinc", arguments + ["consumer.kt", "-d", "consumer.jar"], root: root)
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }

    @Test
    func ownStdlibRepeatableContainerMarker() throws {
        let library = try JVMOwnStdlibCache.shared.library()
        try withWorkspace { root in
            let app = try m22Build(root: root, sources: [("marker.kt", "@Repeatable annotation class Tag(val value: Int)")], name: "marker.jar", mode: .jvmJar, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            try """
            public class MarkerConsumer {
                public static void main(String[] args) {
                    Class<?> container = Tag.class.getAnnotation(java.lang.annotation.Repeatable.class).value();
                    System.out.println(container.isAnnotationPresent(kotlin.jvm.internal.RepeatableContainer.class));
                    System.out.println(kotlin.jvm.internal.RepeatableContainer.class.getAnnotation(java.lang.annotation.Retention.class).value());
                }
            }
            """.write(to: root.appendingPathComponent("MarkerConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", app.0.path + ":" + library.path, "MarkerConsumer.java"], root: root)
            let result = try java(["-cp", root.path + ":" + app.0.path + ":" + library.path, "MarkerConsumer"])
            #expect(result.stdout == "true\nRUNTIME\n")
            #expect(result.stderr.isEmpty)
        }
    }

    @Test
    func ownStdlibLazyConcurrencyAndJavaConsumer() throws {
        let library = try JVMOwnStdlibCache.shared.library()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlibInterop/LazyConsumer.java")
        try withWorkspace { root in
            try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("LazyConsumer.java"))
            _ = try jvmTool("javac", ["-cp", library.path, "LazyConsumer.java"], root: root)
            let result = try java(["-cp", root.path + ":" + library.path, "LazyConsumer"])
            #expect(result.stdout == "lazy modes, monitors, publication, retry and null: OK\n")
            #expect(result.stderr.isEmpty)
        }
    }

    // The external-only fixture uses a source Iterator implementation, which
    // is outside the compiler's current collection declaration surface.
    @Test(arguments: Self.ownStdlibCases + ["sequenceIteratorConsumption"])
    func officialKotlinRuntimeRegression(name: String) throws {
        let library = try JVMOwnStdlibCache.shared.library()
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            try source.write(to: root.appendingPathComponent("hello.kt"), atomically: true, encoding: .utf8)
            // The compiler may use the reference libraries; execution has only
            // the consumer classes and the repository-built runtime.
            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", m11Runtime(), "-d", "consumer.jar"], root: root)
            let package = source.components(separatedBy: "\n").first(where: { $0.hasPrefix("package ") }).map { $0.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines) + "." } ?? ""
            let result = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + library.path, package + "HelloKt"])
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }

}
#endif
