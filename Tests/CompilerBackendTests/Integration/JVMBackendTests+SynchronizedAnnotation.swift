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
    func jvmSynchronizedAnnotationKeepsPrimaryConstructorPropertiesSeparate(mode: EmitMode) throws {
        let source = """
        class Pair(@get:Synchronized @set:Synchronized var first: Int, @get:Synchronized var second: Int, var third: Int)
        class Reverse(var first: Int, @get:Synchronized var second: Int)
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let pair = try javap(["-v", "-p", "-classpath", app.path, "Pair"])
            #expect(pair.exitCode == 0, "\(pair.stderr)")
            #expect(pair.stdout.contains("public final synchronized int getFirst();"), "\(pair.stdout)")
            #expect(pair.stdout.contains("public final synchronized void setFirst(int);"), "\(pair.stdout)")
            #expect(pair.stdout.contains("public final synchronized int getSecond();"), "\(pair.stdout)")
            #expect(!pair.stdout.contains("public final synchronized void setSecond(int);"), "\(pair.stdout)")
            #expect(!pair.stdout.contains("public final synchronized int getThird();"), "\(pair.stdout)")
            #expect(!pair.stdout.contains("public final synchronized void setThird(int);"), "\(pair.stdout)")

            let reverse = try javap(["-v", "-p", "-classpath", app.path, "Reverse"])
            #expect(reverse.exitCode == 0, "\(reverse.stderr)")
            #expect(!reverse.stdout.contains("public final synchronized int getFirst();"), "\(reverse.stdout)")
            #expect(!reverse.stdout.contains("public final synchronized void setFirst(int);"), "\(reverse.stdout)")
            #expect(reverse.stdout.contains("public final synchronized int getSecond();"), "\(reverse.stdout)")
            #expect(!reverse.stdout.contains("public final synchronized void setSecond(int);"), "\(reverse.stdout)")
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
