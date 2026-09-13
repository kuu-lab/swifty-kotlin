#if canImport(Testing)
import Testing

/// Base suite for the `LoweringABIAndPropertyRegressionTests+*` extension
/// files. The shared `runLowering` fixture it used to hold now lives in
/// `TestSupport/Pipeline.swift`, where every lowering suite can reach it.
@Suite
struct LoweringABIAndPropertyRegressionTests {}
#endif
