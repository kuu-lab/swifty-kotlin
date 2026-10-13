# KUU-1859 reference fixtures

`Median.kt` is copied verbatim from TheAlgorithms/Kotlin at commit
`b913c1d85c972fd1e679c5d832d6458b21be8fb0`:

<https://github.com/TheAlgorithms/Kotlin/blob/b913c1d85c972fd1e679c5d832d6458b21be8fb0/src/main/kotlin/math/Median.kt>

`Main.kt` is the consumer supplied with KUU-1859. The minimal and contract
fixtures preserve the issue reproducer and cover FQN calls, in-place sorting,
empty arrays, duplicates, negative values, Int boundaries, and null failure.
Expected output files record the Kotlin/JVM reference results. The upstream
source is MIT licensed; the required notice is in `LICENSE`.
