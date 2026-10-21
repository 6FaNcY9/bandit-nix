{pkgs, ...}: let
  firecrawlKeyFile = "/run/secrets/firecrawl-api-key";

  fcScript = pkgs.writeShellScriptBin "fc" ''
    # Usage: fc <url> [output-file]
    # Scrapes URL via Firecrawl and saves markdown
    set -e
    URL="$1"
    OUT="''${2:-/tmp/fc-content.md}"
    [[ -z "$URL" ]] && { echo "Usage: fc <url> [output-file]" >&2; exit 1; }
    API_KEY=$(cat ${firecrawlKeyFile})
    ${pkgs.curl}/bin/curl -sf --max-time 30 \
      -X POST https://api.firecrawl.dev/v1/scrape \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"url\":\"$URL\",\"formats\":[\"markdown\"]}" \
    | ${pkgs.jq}/bin/jq -r '.data.markdown' > "$OUT"
    echo "Saved to $OUT" >&2
    echo "$OUT"
  '';
in {
  # ── Web helpers ───────────────────────────────────────────────
  home.packages = [fcScript];
}
