#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmSyntheticFunctionsHideFromJavaSourcesAndStayCallableFromKotlin() throws {
        let library = ("SynthLib.kt", """
            package synth

            import kotlin.jvm.JvmName
            import kotlin.jvm.JvmStatic
            import kotlin.jvm.JvmSynthetic

            class SynthLib {
                fun visible(x: Int): Int = x + 1
                @JvmSynthetic fun hidden(x: Int): Int = x + 2
                @JvmSynthetic @JvmName("renamedSynthetic") fun namedSynthetic(x: Int): Int = x + 7

                companion object {
                    @JvmStatic fun compVisible(x: Int): Int = x + 3
                    @JvmStatic @JvmSynthetic fun compHidden(x: Int): Int = x + 4
                }
            }

            @JvmSynthetic fun topHidden(x: Int): Int = x + 5
            fun topVisible(x: Int): Int = x + 6
            """)

        func isSynthetic(_ javapOutput: String, signature: String) -> Bool? {
            guard let signatureRange = javapOutput.range(of: signature) else { return nil }
            let tail = javapOutput[signatureRange.upperBound...]
            guard let flagRange = tail.range(of: "flags: (0x"),
                  let hexEnd = tail[flagRange.upperBound...].range(of: ")")
            else { return nil }
            let hex = tail[flagRange.upperBound..<hexEnd.lowerBound]
            guard let flags = UInt32(hex, radix: 16) else { return nil }
            return flags & 0x1000 != 0
        }

        try withWorkspace { root in
            let compiled = try compile("fun main() {}", root: root, mode: .jvmClass,
                                       additionalSources: [library])
            #expect(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let classes = root.appendingPathComponent("classes")

            let libraryDump = try javap(["-v", "-p", "-classpath", classes.path, "synth.SynthLib"])
            #expect(libraryDump.exitCode == 0, "\(libraryDump.stderr)")
            #expect(isSynthetic(libraryDump.stdout, signature: "int hidden(int);") == true)
            #expect(isSynthetic(libraryDump.stdout, signature: "int visible(int);") == false)
            #expect(isSynthetic(libraryDump.stdout, signature: "int compHidden(int);") == true)
            #expect(isSynthetic(libraryDump.stdout, signature: "int compVisible(int);") == false)
            #expect(isSynthetic(libraryDump.stdout, signature: "int namedSynthetic$jvmName$renamedSynthetic(int);") == true)
            #expect(isSynthetic(libraryDump.stdout, signature: "int renamedSynthetic(int);") == true)

            let companionDump = try javap(["-v", "-p", "-classpath", classes.path, "synth.SynthLib$Companion"])
            #expect(companionDump.exitCode == 0, "\(companionDump.stderr)")
            #expect(isSynthetic(companionDump.stdout, signature: "int compHidden(int);") == true)
            #expect(isSynthetic(companionDump.stdout, signature: "int compVisible(int);") == false)

            let facadeDump = try javap(["-v", "-p", "-classpath", classes.path, "synth.SynthLibKt"])
            #expect(facadeDump.exitCode == 0, "\(facadeDump.stderr)")
            #expect(isSynthetic(facadeDump.stdout, signature: "int topHidden(int);") == true)
            #expect(isSynthetic(facadeDump.stdout, signature: "int topVisible(int);") == false)

            let hiddenCaller = root.appendingPathComponent("JavaHiddenCaller.java")
            try """
            import synth.SynthLib;
            import synth.SynthLibKt;

            public class JavaHiddenCaller {
                public static void main(String[] args) {
                    SynthLib s = new SynthLib();
                    System.out.println(s.hidden(1));
                    System.out.println(s.namedSynthetic(1));
                    System.out.println(SynthLib.compHidden(1));
                    System.out.println(SynthLibKt.topHidden(1));
                }
            }
            """.write(to: hiddenCaller, atomically: true, encoding: .utf8)
            var hiddenRejected = false
            do {
                _ = try javac([
                    "-cp", classes.path,
                    "-d", root.appendingPathComponent("hidden-out").path,
                    hiddenCaller.path,
                ])
            } catch CommandRunnerError.nonZeroExit(let rejection) {
                hiddenRejected = true
                #expect(rejection.stderr.contains("cannot find symbol")
                    || rejection.stdout.contains("cannot find symbol"))
            }
            #expect(hiddenRejected, "javac resolved @JvmSynthetic functions")

            let visibleCaller = root.appendingPathComponent("JavaVisibleCaller.java")
            try """
            import synth.SynthLib;
            import synth.SynthLibKt;

            public class JavaVisibleCaller {
                public static void main(String[] args) {
                    SynthLib s = new SynthLib();
                    System.out.println(s.visible(1));
                    System.out.println(SynthLib.compVisible(1));
                    System.out.println(SynthLibKt.topVisible(1));
                }
            }
            """.write(to: visibleCaller, atomically: true, encoding: .utf8)
            let visibleClasses = root.appendingPathComponent("visible-out")
            let visibleCompilation = try javac([
                "-cp", classes.path,
                "-d", visibleClasses.path,
                visibleCaller.path,
            ])
            #expect(visibleCompilation.exitCode == 0, "\(visibleCompilation.stderr)")
            let visibleExecution = try java(["-cp", classes.path + ":" + visibleClasses.path, "JavaVisibleCaller"])
            #expect(visibleExecution.exitCode == 0, "\(visibleExecution.stderr)")
            #expect(visibleExecution.stdout == "2\n4\n7\n")

            let callerRoot = root.appendingPathComponent("caller")
            try FileManager.default.createDirectory(at: callerRoot, withIntermediateDirectories: true)
            let caller = """
            import synth.*

            fun main() {
                val s = SynthLib()
                println(s.hidden(1))
                println(s.namedSynthetic(1))
                println(s.visible(1))
                println(SynthLib.compHidden(1))
                println(SynthLib.compVisible(1))
                println(topHidden(1))
                println(topVisible(1))
            }
            """
            let callerCompiled = try compile(caller, root: callerRoot, mode: .jvmClass, classpath: [classes.path])
            #expect(callerCompiled.0 == 0, "\(callerCompiled.1.map(\.message))")
            let execution = try java([
                "-cp", callerRoot.appendingPathComponent("classes").path + ":" + classes.path, "HelloKt",
            ])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "3\n8\n2\n5\n4\n6\n7\n")

            let consumer = root.appendingPathComponent("Consumer.kt")
            try """
            import synth.*

            fun main() {
                val s = SynthLib()
                println(s.hidden(1))
                println(s.namedSynthetic(1))
                println(SynthLib.compHidden(1))
                println(topHidden(1))
            }
            """.write(to: consumer, atomically: true, encoding: .utf8)
            let runtime = try m11Runtime()
            var kotlincAccepted = false
            do {
                _ = try jvmTool("kotlinc", [consumer.path, "-cp", classes.path + ":" + runtime, "-d", root.appendingPathComponent("consumer-out").path], root: root)
                kotlincAccepted = true
            } catch {
                #expect(Bool(false), "kotlinc rejected the KSwiftK library: \(error)")
            }
            #expect(kotlincAccepted)
        }
    }
}
#endif
