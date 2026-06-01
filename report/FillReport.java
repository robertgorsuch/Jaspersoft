import net.sf.jasperreports.engine.JasperFillManager;
import net.sf.jasperreports.engine.JasperExportManager;
import net.sf.jasperreports.engine.JasperPrint;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.HashMap;
import java.util.Map;

public class FillReport {
    public static void main(String[] args) throws Exception {
        String jasper = args[0];
        String pdf = args[1];
        Class.forName("org.postgresql.Driver");
        Connection conn = DriverManager.getConnection(
            System.getProperty("db.url","jdbc:postgresql://localhost:5432/postgis_34_sample"), System.getProperty("db.user","postgres"), System.getenv("PGPASSWORD"));
        try {
            Map<String, Object> params = new HashMap<>();
            long t0 = System.currentTimeMillis();
            JasperPrint print = JasperFillManager.fillReport(jasper, params, conn);
            JasperExportManager.exportReportToPdfFile(print, pdf);
            System.out.println("OK: " + pdf + " | pages=" + print.getPages().size()
                + " | fill+export " + (System.currentTimeMillis() - t0) + " ms");
        } finally {
            conn.close();
        }
    }
}
