#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar], [false, true])
    func mainReceivesCommandLineArguments(mode: EmitMode, withNoArgumentMain: Bool) throws {
        try withWorkspace { root in
            let mainWithArguments = """
            fun main(args: Array<String>) {
                println(args.size)
                for (arg in args) {
                    println(arg)
                }
            }
            """
            let source = withNoArgumentMain
                ? "fun main() { println(\"no arguments\") }\n" + mainWithArguments
                : mainWithArguments
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let launch = mode == .jvmJar ? ["-jar", artifact] : ["-cp", artifact, "HelloKt"]
            for (argv, expected) in [
                ([], "0\n"),
                (["a b", "c"], "2\na b\nc\n"),
                (["", "a b", ""], "3\n\na b\n\n"),
            ] {
                let execution = try java(launch + argv)
                #expect(execution.stdout == expected, "argv = \(argv)")
                #expect(execution.stderr.isEmpty)
            }

            let inspection = try javap(["-p", "-s", "-classpath", artifact, "HelloKt"])
            let descriptors = inspection.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(descriptors.filter { $0 == "descriptor: ([Ljava/lang/String;)V" }.count == 1)
            #expect(descriptors.contains("descriptor: ()V") == withNoArgumentMain)
        }
    }
}
#endif
