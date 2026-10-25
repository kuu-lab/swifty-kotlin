fun main() {
    println(java.lang.System.getenv("KSWIFTK_KUU3342_ENV") == "configured")
    println(java.lang.System.getenv()["KSWIFTK_KUU3342_ENV"] == "configured")
    println(java.lang.System.setProperty("kuu3342.key", "first") == null)
    println(java.lang.System.getProperty("kuu3342.key") == "first")
    println(java.lang.System.setProperty("kuu3342.key", "second") == "first")
    println(java.lang.System.clearProperty("kuu3342.key") == "second")
    println(java.lang.System.getProperty("kuu3342.key") == null)
    println(java.lang.System.currentTimeMillis() != 0L)
    println(java.lang.System.nanoTime() != 0L)
}
