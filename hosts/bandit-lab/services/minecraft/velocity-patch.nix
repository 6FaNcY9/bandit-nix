# Applied by itzg to Paper's config at every start (PATCH_DEFINITIONS): modern forwarding from the
# Velocity proxy. The secret is resolved from the environment file (CFG_VELOCITY_SECRET), never written to
# the store. PATCH_DEFINITIONS points at a directory, and itzg reads every file there as one patch
# definition ({file, ops}); a {patches = [...]} patch set is only accepted as a single file and made Paper
# fail to start (2026-10-08). Shared by the real server and the sandbox.
{pkgs}:
pkgs.writeText "velocity-patch.json" (builtins.toJSON {
  file = "/data/config/paper-global.yml";
  ops = [
    {
      "$set" = {
        path = "$.proxies.velocity.enabled";
        value = true;
        value-type = "bool";
      };
    }
    {
      "$set" = {
        path = "$.proxies.velocity.online-mode";
        value = true;
        value-type = "bool";
      };
    }
    {
      "$set" = {
        path = "$.proxies.velocity.secret";
        value = "\${CFG_VELOCITY_SECRET}";
      };
    }
  ];
})
