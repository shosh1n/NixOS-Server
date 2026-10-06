# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, identities, vars ,... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./vars/vars.nix
      ./vars/identities.nix
    ];
  networking.hostName = "nixos";

  nixpkgs.config.allowUnfree = true;
  
  console = {
     font = "Lat2-Terminus16";
  #   keyMap = "us";
     useXkbConfig = true; # use xkb.options in tty.
   };

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
     LC_ADDRESS = "de_DE.utf8";
     LC_IDENTIFICATION = "de_DE.utf8";
     LC_MEASUREMENT = "de_DE.utf8";
     LC_MONETARY = "de_DE.utf8";
     LC_NAME = "de_DE.utf8";
     LC_NUMERIC = "de_DE.utf8";
     LC_PAPER = "de_DE.utf8";
     LC_TELEPHONE = "de_DE.utf8";
     LC_TIME = "de_DE.utf8";
    };
  };

  nix = {
    package = pkgs.nix;
    settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
  };

  services.longview = {
    enable = true;
    apiKeyFile =  "/var/lib/longview/apiKeyFile";
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/var/lib/postgresql/16";
  };
  
  age.secrets."atticd.env" = {
    file = ./secrets/atticd.env.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.atticd = {
    enable = true;
    environmentFile = config.age.secrets."atticd.env".path;
    settings = {
      listen = "${vars.k8sNodeIp}:${toString vars.atticPort}";

      jwt = { };

      chunking = {
        nar-size-threshold = 64 * 1024;
        min-size = 16 * 1024;
        avg-size = 64 * 1024;
        max-size = 256 * 1024;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    age
    htop
    curl
    tmux
    git-crypt
    conda
    openssl
    git
    kubernetes
    cri-tools
    fd
    ripgrep
    gnumake
    inetutils
    hugo
    mtr
    sysstat
    wireguard-tools
  ];

 virtualisation.containerd = {
  enable = true;
  settings = {
    plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
    plugins."io.containerd.grpc.v1.cri".cni.bin_dir = lib.mkForce "/opt/cni/bin";
    };
  };

  system.activationScripts.cni-install = {
    text = # bash
      ''
        ${lib.getExe pkgs.rsync} --recursive --mkpath ${pkgs.cni-plugins}/bin/ /opt/cni/bin/
      '';
  };
  
  systemd.services.kubelet = {
    description = "kubelete: The Kubernetes Node Agent";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "containerd.service" ];
  
    unitConfig = {
      ConditionPathExists = "/var/lib/kubelet/config.yaml";
    };
  
    path = with pkgs; [
      util-linuxMinimal
    ];
  
    serviceConfig = {
      EnvironmentFile = [
        "-/var/lib/kubelet/kubeadm-flags.env"
        "-/etc/sysconfig/kubelet"
      ];
      
  
      ExecStart = "${lib.getExe' pkgs.kubernetes "kubelet"} $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS";
      Restart = "always";
      RestartSec = 1;
      RestartMaxDelaySec = 60;
      RestartSteps = 10;
    };
  
    environment = {
      KUBELET_KUBECONFIG_ARGS =
        "--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf";
      KUBELET_CONFIG_ARGS =
        "--config=/var/lib/kubelet/config.yaml";
      KUBELET_EXTRA_ARGS =
        "--node-ip=${vars.k8sNodeIp}";
    };
  };
  
  services.openssh = {
    enable = true;
    listenAddresses = [
      {
        addr = vars.k8sNodeIp;
        port = 22;
      }
    ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  

  services.fail2ban = {
    extraPackages = [pkgs.ipset];
    banaction = "iptables-ipset-proto6-allports";
    enable = true;
    maxretry = 5;
    ignoreIP = vars.fail2banIgnoreIPs;
    bantime = "24h";
    bantime-increment = {
      enable = true;
      formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
      #multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";
      overalljails = true;
    };
  };

  environment.etc = {

    "fail2ban/filter.d/nginx-bruteforce.conf".text = ''
      [Definition]
      failregex = ^<HOST>.*GET.*(matrix/server|\.php|admin|wp\-).* HTTP/\d.\d\" 404.*$
    '';

    "fail2ban/filter.d/postfix-bruteforce.conf".text = ''
      [Definition]
      failregex = warning: [\w\.\-]+\[<HOST>\]: SASL LOGIN authentication failed.*$
      journalmatch = _SYSTEMD_UNIT=postfix.service
    '';
  };
 services.fail2ban.jails = {

    # max 6 failures in 600 seconds
    "nginx-spam" = ''
      enabled  = true
      filter   = nginx-bruteforce
      logpath = /var/log/nginx/access.log
      backend = auto
      maxretry = 6
      findtime = 600
    '';

    # max 3 failures in 600 seconds
    "postfix-bruteforce" = ''
      enabled = true
      filter = postfix-bruteforce
      findtime = 600
      maxretry = 3
    '';

  };


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.direnv.enable = true;
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  
  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = false;
  networking.interfaces.${vars.netInterface}.useDHCP = true;

  networking.firewall = {
    checkReversePath = "loose";
    trustedInterfaces = [
                         vars.wgHAInterface
                         vars.wgK8sInterface 
                         vars.ciliumHost
                         vars.ciliumNet
                         vars.ciliumVxlan
    ];
    
    allowedUDPPorts = [ vars.wgHAPort vars.wgK8sPort ];
    allowedTCPPorts = vars.allowedTCPPorts;
    interfaces.${vars.wgK8sInterface}.allowedTCPPorts = [
      22
    ];

    extraCommands = ''
      iptables -I INPUT 1 -s ${vars.k8sPodCidr} -j ACCEPT
       iptables -t mangle -I nixos-fw-rpfilter 1 \
         -m mark --mark 0x200/0xf00 \
         -j RETURN
     '';
  };
  
  networking.nat = {
    externalInterface = vars.netInterface;
    internalInterfaces = [ vars.wgK8sInterface ];
  };

  networking.wireguard.interfaces.${vars.wgK8sInterface} = {
      ips = [ "${vars.k8sNodeIp}/24" ];
      listenPort = vars.wgK8sPort;
      privateKeyFile = identities.wgK8sPrivateKeyFile;

      peers = [
        {
          publicKey = identities.wgK8sPeerPublicKey;
          allowedIPs = [ "${vars.k8sAdminIp}/32" ];
          persistentKeepalive = 25;
        }
      ];
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}
