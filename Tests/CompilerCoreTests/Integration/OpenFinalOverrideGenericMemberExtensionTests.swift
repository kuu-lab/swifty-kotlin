#if canImport(Testing)
import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-2260: method type parameters have declaration-local identities, so equivalent
/// member extension overrides must be compared after alpha-alignment.
@Suite
struct OpenFinalOverrideGenericMemberExtensionTests {
    private let validSource = """
    class Box<V, E>(val value: V)
    interface Scope<E> {
        fun <V> Box<V, E>.bind(): V
    }
    class ScopeImpl<E> : Scope<E> {
        override fun <V> Box<V, E>.bind(): V = value
    }

    interface MethodScope<E> {
        fun <V> bind(box: Box<V, E>): V
    }
    class MethodScopeImpl<E> : MethodScope<E> {
        override fun <V> bind(box: Box<V, E>): V = box.value
    }

    class LocalScope<E> {
        fun <V> Box<V, E>.bind(): V = value
    }
    """

    private let bindingScopeSource = """
    package com.github.michaelbull.result
    class Result<V, E>(val value: V)
    interface BindingScope<E> {
        fun <V> Result<V, E>.bind(): V
    }
    class BindingScopeImpl<E> : BindingScope<E> {
        override fun <V> Result<V, E>.bind(): V = value
    }
    """

    private let invalidSource = """
    class Other<V, E>(val value: V)

    interface Bounded<E> {
        fun <V : CharSequence> Box<V, E>.bound(): String
    }
    class WrongBound<E> : Bounded<E> {
        override fun <V : Any> Box<V, E>.bound(): String = "wrong bound"
    }

    interface Receiver<E> {
        fun <V> Box<V, E>.receive(): V
    }
    class WrongReceiver<E> : Receiver<E> {
        override fun <V> Other<V, E>.receive(): V = value
    }

    interface Return<E> {
        fun <V> Box<V, E>.result(): V
    }
    class WrongReturn<E> : Return<E> {
        override fun <V> Box<V, E>.result(): Any = value
    }
    """

    @Test(arguments: [true, false])
    func validatesGenericMemberExtensionOverrides(fromSource: Bool) throws {
        let artifactPath: String?
        if fromSource {
            artifactPath = nil
        } else {
            TestStdlibCache.shared.prepare()
            artifactPath = CompilerOptions.defaultStdlibLibraryPath
        }

        try withTemporaryFiles(contents: [validSource, bindingScopeSource, invalidSource]) { paths in
            let context = makeCompilationContext(
                inputs: paths,
                includeStdlib: artifactPath == nil,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(context)

            let validDiagnostics = diagnosticsForPath(paths[0], in: context)
            #expect(!validDiagnostics.hasError, "Unexpected diagnostics: \(validDiagnostics)")

            let bindingDiagnostics = diagnosticsForPath(paths[1], in: context)
            #expect(!bindingDiagnostics.hasError, "Unexpected BindingScope diagnostics: \(bindingDiagnostics)")

            let invalidDiagnostics = diagnosticsForPath(paths[2], in: context)
            let signatureErrors = invalidDiagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-OVERRIDE-SIGNATURE"
            }
            let returnErrors = invalidDiagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-OVERRIDE-RETURN"
            }
            #expect(signatureErrors.count == 2, "Expected bound and receiver signature errors: \(invalidDiagnostics)")
            #expect(returnErrors.count == 1, "Expected incompatible return type error: \(invalidDiagnostics)")
        }
    }
}
#endif
