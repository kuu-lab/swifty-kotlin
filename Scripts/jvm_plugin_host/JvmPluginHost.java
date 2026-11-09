import java.io.File;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.jar.JarFile;
import java.util.zip.ZipEntry;

/**
 * Lightweight JVM host for loading and querying kotlinc compiler plugin JARs
 * from KSwiftK without requiring external Java dependencies.
 */
public class JvmPluginHost {

    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("Usage: java JvmPluginHost <command> <plugin.jar> [kotlin-compiler.jar] [args...]");
            System.exit(1);
        }

        String command = args[0];
        File pluginJar = new File(args[1]);
        File compilerJar = (args.length > 2 && !args[2].isEmpty() && !args[2].equals("-"))
                ? new File(args[2])
                : null;

        if (!pluginJar.exists()) {
            System.err.println("Plugin JAR not found: " + pluginJar.getAbsolutePath());
            System.exit(2);
        }

        try {
            List<URL> urls = new ArrayList<>();
            urls.add(pluginJar.toURI().toURL());
            if (compilerJar != null && compilerJar.exists()) {
                urls.add(compilerJar.toURI().toURL());
            }

            try (URLClassLoader loader = new URLClassLoader(urls.toArray(new URL[0]), JvmPluginHost.class.getClassLoader());
                 JarFile jar = new JarFile(pluginJar)) {

                if ("inspect".equals(command)) {
                    inspectPlugin(jar, loader);
                } else {
                    System.err.println("Unknown command: " + command);
                    System.exit(3);
                }
            }
        } catch (Throwable t) {
            t.printStackTrace(System.err);
            System.exit(10);
        }
    }

    private static void inspectPlugin(JarFile jar, ClassLoader loader) throws Exception {
        String pluginId = "";
        String commandLineProcessorClass = "";
        List<String> optionsJson = new ArrayList<>();

        ZipEntry cmdProcEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.CommandLineProcessor");
        if (cmdProcEntry != null) {
            try (InputStream is = jar.getInputStream(cmdProcEntry);
                 BufferedReader reader = new BufferedReader(new InputStreamReader(is))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    commandLineProcessorClass = line;
                    try {
                        Class<?> clazz = loader.loadClass(line);
                        Object instance = clazz.getDeclaredConstructor().newInstance();
                        Method getPluginId = clazz.getMethod("getPluginId");
                        pluginId = (String) getPluginId.invoke(instance);

                        Method getOptions = clazz.getMethod("getPluginOptions");
                        Collection<?> options = (Collection<?>) getOptions.invoke(instance);
                        if (options != null) {
                            for (Object opt : options) {
                                Method getOptName = opt.getClass().getMethod("getOptionName");
                                Method getDescription = opt.getClass().getMethod("getDescription");
                                Method isRequiredMethod = null;
                                try {
                                    isRequiredMethod = opt.getClass().getMethod("getRequired");
                                } catch (NoSuchMethodException ignored) {}
                                boolean required = false;
                                if (isRequiredMethod != null) {
                                    Object reqVal = isRequiredMethod.invoke(opt);
                                    if (reqVal instanceof Boolean) {
                                        required = (Boolean) reqVal;
                                    }
                                }

                                String optName = (String) getOptName.invoke(opt);
                                String desc = (String) getDescription.invoke(opt);
                                optionsJson.add(String.format(
                                        "{\"name\":\"%s\",\"description\":\"%s\",\"required\":%b}",
                                        escapeJson(optName), escapeJson(desc), required
                                ));
                            }
                        }
                    } catch (Throwable t) {
                        System.err.println("Warning: failed to inspect CommandLineProcessor: " + t.getMessage());
                    }
                    break;
                }
            }
        }

        String registrarClass = "";
        ZipEntry regEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.CompilerPluginRegistrar");
        if (regEntry == null) {
            regEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.ComponentRegistrar");
        }
        if (regEntry != null) {
            try (InputStream is = jar.getInputStream(regEntry);
                 BufferedReader reader = new BufferedReader(new InputStreamReader(is))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    registrarClass = line;
                    break;
                }
            }
        }

        // Print output as JSON
        StringBuilder sb = new StringBuilder();
        sb.append("{");
        sb.append("\"pluginId\":\"").append(escapeJson(pluginId)).append("\",");
        sb.append("\"commandLineProcessor\":\"").append(escapeJson(commandLineProcessorClass)).append("\",");
        sb.append("\"registrar\":\"").append(escapeJson(registrarClass)).append("\",");
        sb.append("\"options\":[").append(String.join(",", optionsJson)).append("]");
        sb.append("}");

        System.out.println(sb.toString());
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
