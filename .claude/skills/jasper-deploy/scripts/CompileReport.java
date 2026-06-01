import net.sf.jasperreports.engine.JasperCompileManager;

// Compiles a JR7 .jrxml to a .jasper next to the source.
// Run via JDK 11+ single-file source launch:
//   java --class-path "<jasperreports-lib>\*" CompileReport.java <file.jrxml>
public class CompileReport {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: CompileReport <file.jrxml>");
            System.exit(2);
        }
        String src = args[0];
        String dst = src.replaceAll("\\.jrxml$", ".jasper");
        JasperCompileManager.compileReportToFile(src, dst);
        System.out.println("OK: compiled " + src + " -> " + dst);
    }
}
