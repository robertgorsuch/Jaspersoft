import net.sf.jasperreports.engine.JasperCompileManager;

public class CompileReport {
    public static void main(String[] args) throws Exception {
        String src = args[0];
        String dst = src.replaceAll("\\.jrxml$", ".jasper");
        JasperCompileManager.compileReportToFile(src, dst);
        System.out.println("OK: compiled " + src + " -> " + dst);
    }
}
