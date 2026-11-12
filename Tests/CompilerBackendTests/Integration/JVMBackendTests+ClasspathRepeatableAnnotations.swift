#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classpathRepeatableAnnotationUsesTheOriginalContainer() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api;
            import java.lang.annotation.Repeatable;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            @Retention(RetentionPolicy.RUNTIME)
            @Repeatable(Note.Notes.class)
            public @interface Note {
                String value();
                @Retention(RetentionPolicy.RUNTIME)
                public @interface Notes { Note[] value(); }
            }
            """
            try dependency.write(to: root.appendingPathComponent("Note.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            let compiled = try jvmTool("javac", ["-d", classes.path, "Note.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.Note
            @Note("first")
            @Note("second")
            class Subject
            """
            let classpath = [classes.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Subject.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let caller = """
            import api.Note;
            class Runner {
                public static void main(String[] args) {
                    for (Note note : Subject.class.getAnnotationsByType(Note.class)) {
                        System.out.println(note.value());
                    }
                }
            }
            """
            try caller.write(to: root.appendingPathComponent("Runner.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let runner = try jvmTool("javac", ["-cp", runClasspath, "-d", classes.path, "Runner.java"], root: root)
            try #require(runner.exitCode == 0, "\(runner.stderr)")
            let run = try java(["-Xverify:all", "-cp", runClasspath, "Runner"])
            #expect(run.stdout == "first\nsecond\n")
        }
    }
}
#endif
