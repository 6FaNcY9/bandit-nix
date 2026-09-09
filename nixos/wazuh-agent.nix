{pkgs, ...}: let
  # bandit-lab on the tailnet; agent ports 1514/1515 are bound to its
  # tailscale interface only.
  managerAddress = "100.125.161.81";
  stateDir = "/var/lib/wazuh-agent";
  agentImage = "docker.io/wazuh/wazuh-agent:4.14.7";
  # Custom agent configuration: host journald (host journal directory and
  # machine-id are bind-mounted) plus FIM on host paths under /host.
  # CHANGE_* placeholders are substituted by the image entrypoint from the
  # WAZUH_* environment variables on first start.
  ossecConf = pkgs.writeText "wazuh-agent-ossec.conf" ''
    <ossec_config>
      <client>
        <server>
          <address>CHANGE_MANAGER_IP</address>
          <port>CHANGE_MANAGER_PORT</port>
          <protocol>tcp</protocol>
        </server>
        <config-profile>amzn, amzn2023</config-profile>
        <notify_time>20</notify_time>
        <time-reconnect>60</time-reconnect>
        <auto_restart>yes</auto_restart>
        <crypto_method>aes</crypto_method>
        <enrollment>
          <enabled>yes</enabled>
          <manager_address>CHANGE_ENROLL_IP</manager_address>
          <port>CHANGE_ENROLL_PORT</port>
          <agent_name>CHANGE_AGENT_NAME</agent_name>
          <groups>CHANGE_AGENT_GROUP</groups>
        </enrollment>
      </client>

      <client_buffer>
        <disabled>no</disabled>
        <queue_size>5000</queue_size>
        <events_per_second>500</events_per_second>
      </client_buffer>

      <rootcheck>
        <disabled>no</disabled>
        <check_files>yes</check_files>
        <check_trojans>yes</check_trojans>
        <check_dev>yes</check_dev>
        <check_sys>yes</check_sys>
        <check_pids>yes</check_pids>
        <check_ports>yes</check_ports>
        <check_if>yes</check_if>
        <frequency>43200</frequency>
        <rootkit_files>etc/shared/rootkit_files.txt</rootkit_files>
        <rootkit_trojans>etc/shared/rootkit_trojans.txt</rootkit_trojans>
        <skip_nfs>yes</skip_nfs>
      </rootcheck>

      <wodle name="syscollector">
        <disabled>no</disabled>
        <interval>1h</interval>
        <scan_on_start>yes</scan_on_start>
        <hardware>yes</hardware>
        <os>yes</os>
        <network>yes</network>
        <packages>yes</packages>
        <ports all="yes">yes</ports>
        <processes>yes</processes>
        <users>yes</users>
        <groups>yes</groups>
        <services>yes</services>
        <browser_extensions>yes</browser_extensions>
        <synchronization>
          <max_eps>10</max_eps>
        </synchronization>
      </wodle>

      <sca>
        <enabled>yes</enabled>
        <scan_on_start>yes</scan_on_start>
        <interval>12h</interval>
        <skip_nfs>yes</skip_nfs>
      </sca>

      <syscheck>
        <disabled>no</disabled>
        <frequency>43200</frequency>
        <scan_on_start>yes</scan_on_start>

        <directories>/etc,/usr/bin,/usr/sbin</directories>
        <directories>/bin,/sbin,/boot</directories>
        <directories realtime="yes">/host/etc</directories>
        <directories realtime="yes">/host/home</directories>

        <ignore>/etc/mtab</ignore>
        <ignore>/etc/hosts.deny</ignore>
        <ignore>/etc/random-seed</ignore>
        <ignore>/etc/adjtime</ignore>
        <ignore type="sregex">.log$|.swp$</ignore>
        <nodiff>/etc/ssl/private.key</nodiff>

        <skip_nfs>yes</skip_nfs>
        <skip_dev>yes</skip_dev>
        <skip_proc>yes</skip_proc>
        <skip_sys>yes</skip_sys>
        <process_priority>10</process_priority>
        <file_limit>
          <enabled>yes</enabled>
          <entries>500000</entries>
        </file_limit>
        <max_eps>50</max_eps>
        <synchronization>
          <enabled>yes</enabled>
          <interval>5m</interval>
          <max_eps>10</max_eps>
        </synchronization>
      </syscheck>

      <!-- Host journald: security-relevant units only; an unfiltered reader
           floods the agent queue (host container access logs ride journald). -->
      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
        <filter field="_SYSTEMD_UNIT">^sshd\.service$</filter>
      </localfile>
      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
        <filter field="_SYSTEMD_UNIT">^systemd-logind\.service$</filter>
      </localfile>
      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
        <filter field="_SYSTEMD_UNIT">^fail2ban\.service$</filter>
      </localfile>
      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
        <filter field="_SYSTEMD_UNIT">^(smbd|nmbd)\.service$</filter>
      </localfile>
      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
        <filter field="_COMM">^sudo$</filter>
      </localfile>
      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
        <filter field="PRIORITY">^[0-3]$</filter>
      </localfile>

      <localfile>
        <log_format>command</log_format>
        <command>df -P</command>
        <frequency>360</frequency>
      </localfile>

      <active-response>
        <disabled>no</disabled>
        <ca_store>etc/wpk_root.pem</ca_store>
        <ca_verification>yes</ca_verification>
      </active-response>

      <logging>
        <log_format>plain</log_format>
      </logging>

    </ossec_config>

    <ossec_config>
      <localfile>
        <log_format>syslog</log_format>
        <location>/var/ossec/logs/active-responses.log</location>
      </localfile>
    </ossec_config>
  '';
in {
  virtualisation.oci-containers.containers.wazuh-agent = {
    image = agentImage;
    autoStart = true;
    environment = {
      WAZUH_MANAGER_SERVER = managerAddress;
      WAZUH_AGENT_NAME = "bandit";
    };
    volumes = [
      "${stateDir}/etc:/var/ossec/etc"
      "/etc/machine-id:/etc/machine-id:ro"
      "/var/log/journal:/var/log/journal:ro"
      "/etc:/host/etc:ro"
      "/home:/host/home:ro"
      "/root:/host/root:ro"
    ];
  };

  systemd.services.podman-wazuh-agent = {
    after = ["tailscaled.service"];
    wants = ["tailscaled.service"];
    # Persist /var/ossec/etc (client.keys, enrollment state) on the host so a
    # container recreation reuses the same agent identity instead of
    # re-enrolling under a duplicate name. Seed the directory from the image
    # on first start. The custom ossec.conf is (re)installed on every start:
    # the image entrypoint substitutes its CHANGE_* placeholders with the
    # WAZUH_* environment values. Group 999 is the image's wazuh group;
    # wazuh-agentd drops privileges and cannot read a root:root file.
    preStart = ''
      if [ ! -f ${stateDir}/etc/ossec.conf ]; then
        mkdir -p ${stateDir}/etc
        ${pkgs.podman}/bin/podman run --rm \
          -v ${stateDir}/etc:/seed \
          --entrypoint /bin/bash \
          ${agentImage} -c "cp -rp /var/ossec/etc/. /seed/"
      fi
      install -m 0640 -o root -g 999 ${ossecConf} ${stateDir}/etc/ossec.conf
    '';
  };
}
