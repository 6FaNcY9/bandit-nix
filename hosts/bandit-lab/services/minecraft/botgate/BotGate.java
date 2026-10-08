package lab.botgate;

import com.google.inject.Inject;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.PreLoginEvent;
import com.velocitypowered.api.event.connection.PreLoginEvent.PreLoginComponentResult;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import org.slf4j.Logger;

/**
 * Lets names bot0..bot99 skip Mojang authentication, but only when the
 * connection comes from an allowlisted CIDR (env BOTGATE_SOURCES). Every other
 * login is untouched (online mode). Missing or malformed config aborts plugin
 * load, so a broken gate never silently opens or silently stays half-open.
 * Velocity creates this class through Guice; no @Plugin annotation is needed
 * because velocity-plugin.json names the main class.
 */
public final class BotGate {
    private static final Pattern BOT = Pattern.compile("^bot[0-9]{1,2}$");

    private record Cidr(byte[] net, int bits) {
        boolean contains(byte[] ip) {
            if (ip.length != net.length) return false;
            for (int i = 0; i < bits; i++) {
                int m = 0x80 >> (i % 8);
                if ((ip[i / 8] & m) != (net[i / 8] & m)) return false;
            }
            return true;
        }
    }

    private final Logger log;
    private final List<Cidr> sources = new ArrayList<>();

    @Inject
    public BotGate(Logger log) throws Exception {
        this.log = log;
        String env = System.getenv("BOTGATE_SOURCES");
        if (env == null || env.isBlank()) throw new IllegalStateException("BOTGATE_SOURCES is not set");
        for (String s : env.split(",")) {
            String[] p = s.trim().split("/");
            if (p.length != 2) throw new IllegalArgumentException("bad CIDR: " + s);
            if (!p[0].matches("[0-9a-fA-F:.]+")) throw new IllegalArgumentException("not an IP literal: " + s);
            byte[] net = InetAddress.getByName(p[0]).getAddress(); // literal only: no DNS
            int bits = Integer.parseInt(p[1]);
            if (bits < 0 || bits > net.length * 8) throw new IllegalArgumentException("bad prefix: " + s);
            sources.add(new Cidr(net, bits));
        }
    }

    @Subscribe
    public void onPreLogin(PreLoginEvent e) {
        if (!e.getResult().isAllowed() || !BOT.matcher(e.getUsername()).matches()) return;
        if (!(e.getConnection().getRemoteAddress() instanceof InetSocketAddress a)) return;
        byte[] ip = a.getAddress().getAddress();
        for (Cidr c : sources) {
            if (c.contains(ip)) {
                e.setResult(PreLoginComponentResult.forceOfflineMode());
                log.info("botgate: offline login {} from {}", e.getUsername(), a.getAddress().getHostAddress());
                return;
            }
        }
    }
}
