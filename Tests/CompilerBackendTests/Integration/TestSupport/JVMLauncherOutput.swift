@testable import CompilerCore
import Foundation

/// The `java` launcher and JVM print "Picked up ..." notes to stderr for JVM options
/// configured through the environment before the program starts:
/// `NOTE: Picked up JDK_JAVA_OPTIONS: ...` from the launcher, then
/// `Picked up JAVA_TOOL_OPTIONS: ...` / `Picked up _JAVA_OPTIONS: ...` (and
/// `JDK_AOT_VM_OPTIONS` when AOT is enabled) from the VM. Those notes are toolchain
/// output, not program stderr, so JVM execution tests strip exactly the notes the
/// current environment produces and keep every other stderr byte.
extension CommandResult {
    var withoutJavaLauncherNotes: CommandResult {
        withoutJavaLauncherNotes(environment: ProcessInfo.processInfo.environment)
    }

    func withoutJavaLauncherNotes(environment: [String: String]) -> CommandResult {
        var stderr = self.stderr
        let notes = javaLauncherNoteCandidates(in: environment)
        // The launcher/VM print each note at most once, before program output;
        // consume each candidate once so program output resembling a note is kept.
        var consumed = Set<Int>()
        var removedAny = true
        while removedAny {
            removedAny = false
            for (index, note) in notes.enumerated() where !consumed.contains(index) && stderr.hasPrefix(note) {
                stderr.removeFirst(note.count)
                consumed.insert(index)
                removedAny = true
            }
        }
        guard stderr != self.stderr else { return self }
        return CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}

private func javaLauncherNoteCandidates(in environment: [String: String]) -> [String] {
    var notes: [String] = []
    if let value = environment["JDK_JAVA_OPTIONS"] {
        notes.append("NOTE: Picked up JDK_JAVA_OPTIONS: \(value)\n")
    }
    for name in ["JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_AOT_VM_OPTIONS"] {
        if let value = environment[name] {
            notes.append("Picked up \(name): \(value)\n")
        }
    }
    return notes
}
