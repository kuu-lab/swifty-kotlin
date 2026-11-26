#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func launcherNotesAreStrippedButProgramStderrIsKept() {
        let result = CommandResult(
            exitCode: 0,
            stdout: "out\n",
            stderr: "NOTE: Picked up JDK_JAVA_OPTIONS: -Xmx1g\n"
                + "Picked up JAVA_TOOL_OPTIONS: -Xmx2g\n"
                + "Picked up _JAVA_OPTIONS: -Xmx3g\n"
                + "program warning\n"
        )
        let filtered = result.withoutJavaLauncherNotes(environment: [
            "JDK_JAVA_OPTIONS": "-Xmx1g",
            "JAVA_TOOL_OPTIONS": "-Xmx2g",
            "_JAVA_OPTIONS": "-Xmx3g",
        ])
        #expect(filtered.stderr == "program warning\n")
        #expect(filtered.stdout == "out\n")
        #expect(filtered.exitCode == 0)
    }

    @Test
    func launcherNotesWithMultilineValuesAreStripped() {
        let result = CommandResult(
            exitCode: 0,
            stdout: "",
            stderr: "NOTE: Picked up JDK_JAVA_OPTIONS: -Xmx1g\n-XX:+UseSerialGC\nreal\n"
        )
        let filtered = result.withoutJavaLauncherNotes(environment: [
            "JDK_JAVA_OPTIONS": "-Xmx1g\n-XX:+UseSerialGC",
        ])
        #expect(filtered.stderr == "real\n")
    }

    @Test
    func launcherNotesAreOnlyStrippedWhenEnvironmentSetsThem() {
        let stderr = "NOTE: Picked up JDK_JAVA_OPTIONS: -Xmx1g\nprogram warning\n"
        let result = CommandResult(exitCode: 0, stdout: "", stderr: stderr)
        #expect(result.withoutJavaLauncherNotes(environment: [:]).stderr == stderr)
        let later = CommandResult(exitCode: 0, stdout: "", stderr: "first\n" + stderr)
        #expect(later.withoutJavaLauncherNotes(environment: ["JDK_JAVA_OPTIONS": "-Xmx1g"]).stderr == later.stderr)
    }

    @Test
    func launcherNotePrintedByProgramIsKept() {
        let environment = ["JDK_JAVA_OPTIONS": "-Xmx1g", "JAVA_TOOL_OPTIONS": "-Xmx2g"]
        let jdkNote = "NOTE: Picked up JDK_JAVA_OPTIONS: -Xmx1g\n"
        let toolNote = "Picked up JAVA_TOOL_OPTIONS: -Xmx2g\n"
        let result = CommandResult(exitCode: 0, stdout: "", stderr: jdkNote + toolNote + toolNote + "real\n")
        #expect(result.withoutJavaLauncherNotes(environment: environment).stderr == toolNote + "real\n")
    }

    @Test
    func programStderrIsStillDetectedAfterLauncherNotes() throws {
        try withWorkspace { root in
            try """
            public class StderrProbe {
                public static void main(String[] args) {
                    System.err.println("real program stderr");
                    System.out.println("probe stdout");
                }
            }
            """.write(to: root.appendingPathComponent("StderrProbe.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["StderrProbe.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-cp", root.path, "StderrProbe"])
            #expect(run.stdout == "probe stdout\n")
            #expect(run.stderr == "real program stderr\n")
        }
    }
}
#endif
