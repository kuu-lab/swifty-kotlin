package golden.diagnostics

// KSP-733: the bundled kotlin.ExperimentalContextParameters marker should render its
// custom @RequiresOptIn message with decoded quotes (not escaped backslashes).

@kotlin.ExperimentalContextParameters
fun contextParamsApi(): Int = 1

// Usage without opt-in should report an error diagnostic.
fun useContextParams(): Int = contextParamsApi()
