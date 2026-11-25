@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LLVMCAPIBindingsUsableCandidateTests {
    private final class Recorder {
        var bound: [String] = []
        var smokeTested: [String] = []
        var diagnostics: [String] = []
    }

    private static func select(
        candidates: [String],
        unbindable: Set<String> = [],
        failingSmokeTest: Set<String>,
        recorder: Recorder
    ) -> String? {
        LLVMCAPIBindings.firstUsable(
            candidates: candidates,
            bind: { candidate -> String? in
                recorder.bound.append(candidate)
                return unbindable.contains(candidate) ? nil : candidate
            },
            isUsable: { candidate in
                recorder.smokeTested.append(candidate)
                return !failingSmokeTest.contains(candidate)
            },
            diagnose: { recorder.diagnostics.append($0) }
        )
    }

    @Test
    func smokeTestFailureFallsBackToNextCandidateAndNamesTheSkippedLibrary() {
        let recorder = Recorder()
        let selected = Self.select(
            candidates: ["/opt/broken/libLLVM.dylib", "/opt/good/libLLVM.dylib", "/opt/unused/libLLVM.dylib"],
            failingSmokeTest: ["/opt/broken/libLLVM.dylib"],
            recorder: recorder
        )

        #expect(selected == "/opt/good/libLLVM.dylib")
        #expect(recorder.bound == ["/opt/broken/libLLVM.dylib", "/opt/good/libLLVM.dylib"])
        #expect(recorder.diagnostics == [
            "kswiftc: skipping LLVM library candidate /opt/broken/libLLVM.dylib: LLVMContextCreate returned null\n",
        ])
    }

    @Test
    func everySmokeTestFailureIsReportedWhenNoCandidateIsUsable() {
        let recorder = Recorder()
        let selected = Self.select(
            candidates: ["/a/libLLVM.so", "/b/libLLVM.so", "/c/libLLVM.so"],
            unbindable: ["/b/libLLVM.so"],
            failingSmokeTest: ["/a/libLLVM.so", "/c/libLLVM.so"],
            recorder: recorder
        )

        #expect(selected == nil)
        #expect(recorder.smokeTested == ["/a/libLLVM.so", "/c/libLLVM.so"])
        #expect(recorder.diagnostics == [
            LLVMCAPIBindings.smokeTestFailedDiagnostic(libraryPath: "/a/libLLVM.so"),
            LLVMCAPIBindings.smokeTestFailedDiagnostic(libraryPath: "/c/libLLVM.so"),
        ])
    }

    @Test
    func unbindableCandidatesAreNotSmokeTestedOrReportedHere() {
        let recorder = Recorder()
        let selected = Self.select(
            candidates: ["/missing/libLLVM.so", "/ok/libLLVM.so"],
            unbindable: ["/missing/libLLVM.so"],
            failingSmokeTest: [],
            recorder: recorder
        )

        #expect(selected == "/ok/libLLVM.so")
        #expect(recorder.smokeTested == ["/ok/libLLVM.so"])
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func relativeOverrideIsRejectedWithDiagnostic() {
        let override = LLVMCAPIBindings.libraryOverride(environment: ["KSWIFTK_LLVM_DYLIB": "relative/dir/libLLVM.so"])

        #expect(override == .rejected(
            diagnostic: "kswiftc: skipping LLVM library candidate relative/dir/libLLVM.so from KSWIFTK_LLVM_DYLIB: path is not absolute\n"
        ))
    }

    @Test
    func missingOverrideIsRejectedWithDiagnostic() {
        let missing = "/tmp/does-not-exist-kswiftk-\(UUID().uuidString).dylib"
        let resolved = URL(fileURLWithPath: missing).standardized.path

        let override = LLVMCAPIBindings.libraryOverride(environment: ["KSWIFTK_LLVM_DYLIB": missing])

        #expect(override == .rejected(
            diagnostic: "kswiftc: skipping LLVM library candidate \(resolved) from KSWIFTK_LLVM_DYLIB: file does not exist\n"
        ))
    }

    @Test
    func unsetOrEmptyOverrideIsSilent() {
        #expect(LLVMCAPIBindings.libraryOverride(environment: [:]) == .unset)
        #expect(LLVMCAPIBindings.libraryOverride(environment: ["KSWIFTK_LLVM_DYLIB": ""]) == .unset)
    }

    @Test
    func existingAbsoluteOverrideIsAcceptedAndListedFirst() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".dylib")
        _ = FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let resolved = tempURL.standardized.path

        let environment = ["KSWIFTK_LLVM_DYLIB": tempURL.path]

        #expect(LLVMCAPIBindings.libraryOverride(environment: environment) == .accepted(path: resolved))
        #expect(LLVMCAPIBindings.candidateLibraryPaths(environment: environment).first == resolved)
    }

    @Test
    func loadUsableReportsRejectedOverride() {
        var diagnostics: [String] = []

        _ = LLVMCAPIBindings.loadUsable(
            environment: ["KSWIFTK_LLVM_DYLIB": "relative/libLLVM.so"],
            diagnose: { diagnostics.append($0) }
        )

        #expect(diagnostics.first
            == "kswiftc: skipping LLVM library candidate relative/libLLVM.so from KSWIFTK_LLVM_DYLIB: path is not absolute\n")
    }
}
