#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmSynchronizedAnnotationResolvesAndMarksMethods(mode: EmitMode) throws {
        let source = """
        class Counter {
            @get:Synchronized
            var value = 0
                private set

            @Synchronized
            fun touch() {
                value += 1
            }
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let inspection = try javap(["-v", "-p", "-classpath", app.path, "Counter"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("public final synchronized void touch();"), "\(inspection.stdout)")
            #expect(inspection.stdout.contains("public final synchronized int getValue();"), "\(inspection.stdout)")
            #expect(!inspection.stdout.contains("private final synchronized void setValue"), "\(inspection.stdout)")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmSynchronizedAnnotationMarksPrimaryConstructorAccessors(mode: EmitMode) throws {
        let source = "class Counter(@get:Synchronized @set:Synchronized var value: Int)"
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let inspection = try javap(["-v", "-p", "-classpath", app.path, "Counter"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("public final synchronized int getValue();"), "\(inspection.stdout)")
            #expect(inspection.stdout.contains("public final synchronized void setValue(int);"), "\(inspection.stdout)")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmSynchronizedAnnotationRejectsInterfaceMembers(mode: EmitMode) throws {
        let source = """
        interface Counter {
            @Synchronized fun touch() {}
            @get:Synchronized val value: Int
                get() = 1
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 1)
            #expect(result.1.contains {
                $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" && $0.message.contains("cannot be used on interface members")
            }, "\(result.1.map(\.message))")
        }
    }
}
#endif
