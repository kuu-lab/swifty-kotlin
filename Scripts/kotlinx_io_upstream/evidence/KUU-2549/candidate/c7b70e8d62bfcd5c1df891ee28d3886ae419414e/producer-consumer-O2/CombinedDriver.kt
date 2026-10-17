fun main() {
    println("KIO_266adcb9805f2a03f5bc6157 BEGIN kotlinx.io.samples.KotlinxIoCoreCommonSamples.startsWithSample")
    try {
        kotlinx.io.samples.KotlinxIoCoreCommonSamples().startsWithSample()
        println("KIO_266adcb9805f2a03f5bc6157 PASS kotlinx.io.samples.KotlinxIoCoreCommonSamples.startsWithSample")
    } catch (failure: Throwable) {
        println("KIO_266adcb9805f2a03f5bc6157 FAIL kotlinx.io.samples.KotlinxIoCoreCommonSamples.startsWithSample")
        println("KIO_266adcb9805f2a03f5bc6157 EXCEPTION " + failure::class.qualifiedName)
    }
}
