@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LLVMCAPIBindingsLoadingTests {
    private static func bind(withoutSymbols absent: Set<String>) -> Result<LLVMCAPIBindings, LLVMCAPIBindings.MissingRequiredSymbols> {
        let presentSymbol = UnsafeMutableRawPointer(bitPattern: 0x10)!
        return LLVMCAPIBindings.makeBindings(
            handle: UnsafeMutableRawPointer(bitPattern: 0x1)!,
            libraryPath: "/opt/llvm/lib/libLLVM.dylib",
            lookup: { absent.contains($0) ? nil : presentSymbol }
        )
    }

    @Test
    func missingRequiredSymbolsAreAllNamedInDeclarationOrder() {
        let result = Self.bind(withoutSymbols: [
            "LLVMTargetMachineEmitToFile",
            "LLVMContextCreate",
            "LLVMGetTargetFromTriple",
        ])

        guard case .failure(let missing) = result else {
            Issue.record("binding must fail when required symbols are absent")
            return
        }
        #expect(missing.names == [
            "LLVMContextCreate",
            "LLVMGetTargetFromTriple",
            "LLVMTargetMachineEmitToFile",
        ])
    }

    @Test
    func missingOptionalSymbolsAreNotReportedAsRequired() {
        let result = Self.bind(withoutSymbols: [
            "LLVMDisposeTargetData",
            "LLVMBuildCall2",
            "LLVMRunPasses",
            "LLVMCreateDIBuilder",
        ])

        guard case .failure(let missing) = result else {
            Issue.record("binding must fail when a required symbol is absent")
            return
        }
        #expect(missing.names == ["LLVMDisposeTargetData"])
    }

    @Test
    func missingRequiredSymbolsDiagnosticNamesLibraryAndSymbols() {
        let message = LLVMCAPIBindings.missingRequiredSymbolsDiagnostic(
            libraryPath: "/usr/lib/llvm-14/lib/libLLVM.so",
            missing: ["LLVMGetTargetFromTriple", "LLVMTargetMachineEmitToFile"]
        )

        #expect(message == "kswiftc: skipping LLVM library candidate /usr/lib/llvm-14/lib/libLLVM.so: "
            + "missing required symbols: LLVMGetTargetFromTriple, LLVMTargetMachineEmitToFile\n")
    }
}
