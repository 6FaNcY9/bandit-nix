# Secret isolation between hosts (docs/runbooks/sops-split.md).
#
# Evaluation-time: each host reads only its own sops files, and every secret a
# host declares exists as a top-level key in the file it is read from.
# Build-time (cleartext sops metadata only, nothing is decrypted): the
# recipients recorded in each file keep the host keys apart, and the rules in
# .sops.yaml end in a user-only catch-all.
{
  pkgs,
  lib,
  hosts,
}: let
  # Files each host may read. Anything else under secrets/ is rejected below.
  allowedFiles = {
    bandit = ["bandit.yaml" "github.yaml"];
    bandit-lab = ["lab.yaml"];
  };

  # ponytail: legacy shared file, tolerated only until the split cleanup
  # commit deletes it (runbook step 4). Drop this entry then.
  legacyFiles = ["secrets.yaml"];

  # ponytail: github.yaml still lists the lab key until the cleanup step
  # re-keys it (the lab must stop referencing it first). Drop this entry then.
  tolerateLabRecipient = ["github.yaml"];

  declaredByFile = host: let
    secrets = lib.attrValues hosts.${host}.config.sops.secrets;
    files = lib.unique (map (s: baseNameOf (toString s.sopsFile)) secrets);
  in
    lib.genAttrs files (file:
      lib.sort lib.lessThan (map (s: s.key)
        (lib.filter (s: baseNameOf (toString s.sopsFile) == file) secrets)));

  perHost = lib.mapAttrs (host: allowed: let
    declared = declaredByFile host;
    foreign = lib.subtractLists allowed (lib.attrNames declared);
  in
    assert lib.assertMsg (foreign == [])
    "${host} reads sops files it must not decrypt: ${toString foreign}"; declared)
  allowedFiles;

  # file -> declared key names, merged across hosts (user-password and
  # thehost-sshkey legitimately exist in more than one file).
  declared =
    lib.foldl' (acc: host:
      acc // (lib.mapAttrs (_: names: names) perHost.${host})) {} (lib.attrNames perHost);
in
  pkgs.runCommand "sops-isolation" {
    nativeBuildInputs = [pkgs.yq-go pkgs.jq];
    declaredJson = builtins.toJSON declared;
    legacy = toString legacyFiles;
    tolerateLab = toString tolerateLabRecipient;
    # The lab must not be able to decrypt anything it does not declare.
    exactFiles = "lab.yaml";
  } ''
    set -euo pipefail
    cp ${../.sops.yaml} sops.yaml
    cp -r ${../secrets} secrets

    bandit=$(sed -n 's/.*&host_bandit \(age1[a-z0-9]*\).*/\1/p' sops.yaml)
    lab=$(sed -n 's/.*&host_bandit_lab \(age1[a-z0-9]*\).*/\1/p' sops.yaml)
    [[ -n $bandit && -n $lab && $bandit != "$lab" ]] || { echo "host recipients not found in .sops.yaml" >&2; exit 1; }

    # Catch-all must be last and user-only so a stray file fails safe.
    n=$(yq '.creation_rules[-1].key_groups[0].age | length' sops.yaml)
    [[ $n == 1 ]] || { echo ".sops.yaml catch-all must encrypt to the user key only" >&2; exit 1; }

    recipients() { yq '.sops.age[].recipient' "$1"; }

    for f in secrets/*.yaml; do
      name=$(basename "$f")
      case " $legacy " in *" $name "*) continue ;; esac
      r=$(recipients "$f")
      has_bandit=0; has_lab=0
      grep -qx "$bandit" <<<"$r" && has_bandit=1
      grep -qx "$lab" <<<"$r" && has_lab=1
      case "$name" in
        lab.yaml) want="0 1" ;;
        bandit.yaml|github.yaml) want="1 0" ;;
        *) echo "unexpected secrets file $name: add it to the isolation policy" >&2; exit 1 ;;
      esac
      case " $tolerateLab " in *" $name "*) [[ $has_lab == 1 ]] && want="1 1" ;; esac
      [[ "$has_bandit $has_lab" == "$want" ]] || {
        echo "$name has wrong host recipients (bandit/lab = $has_bandit/$has_lab, want $want)" >&2; exit 1; }
    done

    # Declared keys must exist in their file; lab.yaml must hold nothing else.
    for name in $(jq -r 'keys[]' <<<"$declaredJson"); do
      file=secrets/$name
      [[ -f $file ]] || { echo "$name is declared by a host but missing" >&2; exit 1; }
      have=$(yq 'keys | .[] | select(. != "sops")' "$file" | sort)
      want=$(jq -r --arg n "$name" '.[$n][]' <<<"$declaredJson" | sort)
      missing=$(comm -13 <(echo "$have") <(echo "$want"))
      [[ -z $missing ]] || { echo "$name lacks declared keys: $missing" >&2; exit 1; }
      case " $exactFiles " in *" $name "*)
        extra=$(comm -23 <(echo "$have") <(echo "$want"))
        [[ -z $extra ]] || { echo "$name holds keys no module declares: $extra" >&2; exit 1; } ;;
      esac
    done
    touch "$out"
  ''
