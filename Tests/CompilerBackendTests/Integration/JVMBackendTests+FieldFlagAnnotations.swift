#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmFieldFlagAnnotationsResolveAndMarkFields(mode: EmitMode) throws {
        let source = """
        class FieldFlags {
            @Volatile var volatileValue = 1
            @Transient var transientValue = 2
            @field:kotlin.jvm.Volatile var explicitVolatile = 3
            @field:kotlin.jvm.Transient var explicitTransient = 4
        }
        class ConstructorFlags(
            @Volatile var volatileValue: Int,
            @field:kotlin.jvm.Transient var transientValue: Int
        )
        class DelegatedFlags {
            @delegate:kotlin.jvm.Transient val value by lazy { "x" }
        }
        """
        let cases: [(String, [String])] = [
            ("FieldFlags", [
                "volatile int volatileValue",
                "transient int transientValue",
                "volatile int explicitVolatile",
                "transient int explicitTransient",
            ]),
            ("ConstructorFlags", [
                "volatile int volatileValue",
                "transient int transientValue",
            ]),
            ("DelegatedFlags", [
                "transient kotlin.Lazy value$delegate",
            ]),
        ]
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            for (className, expectedFieldLines) in cases {
                let inspection = try javap(["-p", "-classpath", app.path, className])
                try #require(inspection.exitCode == 0, "\(inspection.stderr)")
                for line in expectedFieldLines {
                    #expect(inspection.stdout.contains(line), "\(className): \(line) missing from:\n\(inspection.stdout)")
                }
            }

            let reference = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let referenceJar = root.appendingPathComponent("reference.jar").path
            for (className, expectedFieldLines) in cases {
                let referenceInspection = try javap(["-p", "-classpath", referenceJar, className])
                try #require(referenceInspection.exitCode == 0, "\(referenceInspection.stderr)")
                for line in expectedFieldLines {
                    #expect(referenceInspection.stdout.contains(line), "kotlinc reference \(className) missing \(line):\n\(referenceInspection.stdout)")
                }
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmFieldFlagAnnotationsRejectInvalidVolatile(mode: EmitMode) throws {
        try withWorkspace { root in
            let immutable = "class InvalidVal { @Volatile val value = 1 }"
            let immutableResult = try compile(immutable, root: root, mode: mode)
            try #require(immutableResult.0 != 0)
            let immutableMessage = immutableResult.1.map(\.message).joined(separator: "\n")
            #expect(immutableMessage.contains("cannot be used on immutable properties"), "\(immutableMessage)")

            let immutableReference: CommandResult
            do {
                immutableReference = try jvmTool("kotlinc", ["hello.kt", "-d", "reference-immutable.jar"], root: root)
            } catch let CommandRunnerError.nonZeroExit(result) {
                immutableReference = result
            }
            try #require(immutableReference.exitCode != 0, "\(immutableReference.stderr)")
            #expect(immutableReference.stderr.contains("cannot be used on immutable properties"), "\(immutableReference.stderr)")
        }

        try withWorkspace { root in
            let delegated = "class InvalidDelegate { @delegate:kotlin.jvm.Volatile var value by kotlin.properties.Delegates.observable(0) { _, _, _ -> } }"
            let delegatedResult = try compile(delegated, root: root, mode: mode)
            try #require(delegatedResult.0 != 0)
            let delegatedMessage = delegatedResult.1.map(\.message).joined(separator: "\n")
            #expect(delegatedMessage.contains("cannot be used on delegated properties"), "\(delegatedMessage)")

            let delegatedReference: CommandResult
            do {
                delegatedReference = try jvmTool("kotlinc", ["hello.kt", "-d", "reference-delegated.jar"], root: root)
            } catch let CommandRunnerError.nonZeroExit(result) {
                delegatedReference = result
            }
            try #require(delegatedReference.exitCode != 0, "\(delegatedReference.stderr)")
            #expect(delegatedReference.stderr.contains("cannot be used on delegated properties"), "\(delegatedReference.stderr)")
        }

        try withWorkspace { root in
            let constructorArguments = """
            class ConstructorVolatileArgument(@Volatile(1) var volatileValue: Int)
            class ConstructorTransientArgument(@field:kotlin.jvm.Transient(1) var transientValue: Int)
            """
            let constructorArgumentsResult = try compile(constructorArguments, root: root, mode: mode)
            try #require(constructorArgumentsResult.0 != 0)
            let constructorArgumentsMessage = constructorArgumentsResult.1.map(\.message).joined(separator: "\n")
            #expect(constructorArgumentsMessage.contains("Too many arguments"), "\(constructorArgumentsMessage)")

            let constructorArgumentsReference: CommandResult
            do {
                constructorArgumentsReference = try jvmTool("kotlinc", ["hello.kt", "-d", "reference-constructor-arguments.jar"], root: root)
            } catch let CommandRunnerError.nonZeroExit(result) {
                constructorArgumentsReference = result
            }
            try #require(constructorArgumentsReference.exitCode != 0, "\(constructorArgumentsReference.stderr)")
            #expect(constructorArgumentsReference.stderr.contains("too many arguments"), "\(constructorArgumentsReference.stderr)")
        }

        try withWorkspace { root in
            let annotationElements = """
            annotation class FieldAnnotation(@field:kotlin.jvm.Transient val value: Int)
            annotation class PlainAnnotation(@Transient val value: Int)
            """
            let annotationElementsResult = try compile(annotationElements, root: root, mode: mode)
            try #require(annotationElementsResult.0 != 0)
            let annotationElementsMessage = annotationElementsResult.1.map(\.message).joined(separator: "\n")
            #expect(annotationElementsMessage.contains("not applicable"), "\(annotationElementsMessage)")

            let annotationElementsReference: CommandResult
            do {
                annotationElementsReference = try jvmTool("kotlinc", ["hello.kt", "-d", "reference-annotation-elements.jar"], root: root)
            } catch let CommandRunnerError.nonZeroExit(result) {
                annotationElementsReference = result
            }
            try #require(annotationElementsReference.exitCode != 0, "\(annotationElementsReference.stderr)")
            #expect(annotationElementsReference.stderr.contains("not applicable"), "\(annotationElementsReference.stderr)")
        }
    }
}
#endif
