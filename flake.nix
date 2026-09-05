{
  description = "NixOS module for Brother MFC-9970CDW printer";

  outputs = { self, nixpkgs }:
    let
      # Official Brother brscan4 driver, downloaded at build time.
      # Version 0.4.11-1 includes the MFC-9970CDW model (unlike nixpkgs 0.4.10-1).
      #
      # Source: https://support.brother.com/
      # Direct URL: https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
      #
      # To update the sha256 hash after changing the version:
      #   nix-prefetch-url https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
      brscan4Src = nixpkgs: nixpkgs.fetchurl {
        url = "https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb";
        sha256 = "sha256-AntzZIcirIyOsanEGdKEplYsx2P+rJdAordaaDsJKXI=";  # Fill in after first build (Nix will print the expected hash).
      };

      # Extracted .deb contents with SANE library relocated to the standard
      # $out/lib/sane/ path expected by hardware.sane.extraBackends.
      brscan4Drv = pkgs:
        pkgs.runCommand "brscan4-official-0.4.11-1" {
          nativeBuildInputs = [ pkgs.dpkg ];
        } ''
          dpkg-deb -x ${brscan4Src pkgs} $out
          mkdir -p $out/lib $out/etc/sane.d/dll.d
          ln -s $out/usr/lib64/sane $out/lib/sane
          echo brother4 > $out/etc/sane.d/dll.d/brother4.conf
        '';
    in
    {
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.hardware.printers.brotherMfc9970cdw;

          # Extracted official driver (available when scannerBackend = "brscan4").
          brscan4Pkg = brscan4Drv pkgs;
        in
        {
          options.hardware.printers.brotherMfc9970cdw = {
            enable = lib.mkEnableOption "Brother MFC-9970CDW network printer";

            ipAddress = lib.mkOption {
              type = lib.types.str;
              example = "192.168.1.15";
              description = ''
                IP address of the Brother MFC-9970CDW printer on the local network.
              '';
            };

            defaultPrinter = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to set this printer as the CUPS default.";
            };

            duplexMode = lib.mkOption {
              type = lib.types.enum [ "DuplexNoTumble" "DuplexTumble" "None" ];
              default = "DuplexNoTumble";
              description = ''
                Duplex printing mode. `DuplexNoTumble` for long-edge binding (letter/A4),
                `DuplexTumble` for short-edge (landscape/notepad), `None` to disable.
              '';
            };

            location = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "home office";
              description = "Human-readable location label for the printer.";
            };

            enableScanner = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Enable scanning support for the Brother MFC-9970CDW.
                Uses sane-airscan (eSCL/AirScan protocol) by default.
              '';
            };

            scannerBackend = lib.mkOption {
              type = lib.types.enum [ "airscan" "brscan4" "brscan5" ];
              default = "airscan";
              description = ''
                Scanner backend to use. `airscan` (eSCL/AirScan, recommended) or
                `brscan4` / `brscan5` (Brother proprietary drivers).
                `brscan4` downloads the official Brother .deb (0.4.11-1) which
                includes the MFC-9970CDW model.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            services.printing.enable = true;

            hardware.printers = {
              ensureDefaultPrinter = lib.mkIf cfg.defaultPrinter "Brother_MFC-9970CDW";
              ensurePrinters = [
                {
                  deviceUri = "socket://${cfg.ipAddress}:9100";
                  name = "Brother_MFC-9970CDW";
                  model = "drv:///sample.drv/generic.ppd";
                  location = cfg.location;
                  ppdOptions = {
                    Duplex = cfg.duplexMode;
                    Option1 = "True";
                  };
                }
              ];
            };

            hardware.sane = lib.mkIf cfg.enableScanner {
              enable = true;
              extraBackends = [
                (if cfg.scannerBackend == "airscan" then pkgs.sane-airscan
                 else if cfg.scannerBackend == "brscan4" then brscan4Pkg
                 else pkgs.brscan5)
              ];
            };

            # SANE reads dll.d from the sane-backends store path. The
            # hardware.sane module creates a sane-config package that includes
            # all backends, but scanimage from simple-scan's sane-backends dep
            # doesn't use it. We write a combined dll.conf to /etc/sane.d
            # and tell SANE to look there via SANE_CONFIG_DIR.
            environment.etc = lib.mkIf cfg.enableScanner {
              "sane.d/dll.conf" = {
                text =
                  let
                    saneDllConf = builtins.readFile "${pkgs.sane-backends}/etc/sane.d/dll.conf";
                    backend = if cfg.scannerBackend == "brscan4" then "brother4"
                      else if cfg.scannerBackend == "brscan5" then "brother5"
                      else "airscan";
                  in
                    saneDllConf + "\n" + backend + "\n";
              };
            };

            environment.sessionVariables = lib.mkIf cfg.enableScanner {
              SANE_CONFIG_DIR = "/etc/sane.d";
            };

            # Brother's proprietary SANE backends need support files at
            # /opt/brother/scanner/brscanN/. We symlink individual files from
            # the extracted driver so we can also write the device config there.
            systemd.tmpfiles.rules = lib.mkIf cfg.enableScanner (
              if cfg.scannerBackend == "brscan4" then
                let src = "${brscan4Pkg}/opt/brother/scanner/brscan4";
                in [
                  "d /opt/brother/scanner/brscan4 0755 root root -"
                  "L+ /opt/brother/scanner/brscan4/Brsane4.ini - - - - ${src}/Brsane4.ini"
                  "L+ /opt/brother/scanner/brscan4/models4 - - - - ${src}/models4"
                  "L+ /opt/brother/scanner/brscan4/doc - - - - ${src}/doc"
                  "L+ /opt/brother/scanner/brscan4/brscan_cnetconfig - - - - ${src}/brscan_cnetconfig"
                  "L+ /opt/brother/scanner/brscan4/brscan_gnetconfig - - - - ${src}/brscan_gnetconfig"
                  "L+ /opt/brother/scanner/brscan4/setupSaneScan4 - - - - ${src}/setupSaneScan4"
                  "L+ /opt/brother/scanner/brscan4/udev_config.sh - - - - ${src}/udev_config.sh"
                  "L+ /opt/brother/scanner/brscan4/brsaneconfig4 - - - - ${src}/brsaneconfig4"
                  "f+ /opt/brother/scanner/brscan4/brsanenetdevice4.cfg 0644 root root - DEV=eth,0,\"Brother_MFC-9970CDW\",${cfg.ipAddress},\"MFC-9970CDW\""
                ]
              else if cfg.scannerBackend == "brscan5" then
                let src = "${pkgs.brscan5}/opt/brother/scanner/brscan5";
                in [
                  "d /opt/brother/scanner/brscan5 0755 root root -"
                  "L+ /opt/brother/scanner/brscan5/brscan5.ini - - - - ${src}/brscan5.ini"
                  "L+ /opt/brother/scanner/brscan5/models - - - - ${src}/models"
                  "L+ /opt/brother/scanner/brscan5/doc - - - - ${src}/doc"
                  "L+ /opt/brother/scanner/brscan5/brscan_cnetconfig - - - - ${src}/brscan_cnetconfig"
                  "L+ /opt/brother/scanner/brscan5/brscan_gnetconfig - - - - ${src}/brscan_gnetconfig"
                  "L+ /opt/brother/scanner/brscan5/setupSaneScan5 - - - - ${src}/setupSaneScan5"
                  "L+ /opt/brother/scanner/brscan5/brsaneconfig5 - - - - ${src}/brsaneconfig5"
                  "f+ /opt/brother/scanner/brscan5/brsanenetdevice.cfg 0644 root root - DEV=eth,0,\"Brother_MFC-9970CDW\",${cfg.ipAddress},\"MFC-9970CDW\""
                ]
              else []
            );
          };
        };
    };
}
