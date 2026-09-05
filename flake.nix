{
  description = "NixOS module for Brother MFC-9970CDW printer";

  outputs = { self, nixpkgs }: {
    nixosModules.default = { config, lib, pkgs, ... }:
      let
        cfg = config.hardware.printers.brotherMfc9970cdw;
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
               else if cfg.scannerBackend == "brscan4" then pkgs.brscan4
               else pkgs.brscan5)
            ];
          };

          # Brother's proprietary SANE backends look for support files at
          # /opt/brother/scanner/brscanN/ — symlink there from the store.
          systemd.tmpfiles.rules = lib.mkIf cfg.enableScanner (
            if cfg.scannerBackend == "brscan4" then [
              "L /opt/brother/scanner/brscan4 - - - - ${pkgs.brscan4}/opt/brother/scanner/brscan4"
            ] else if cfg.scannerBackend == "brscan5" then [
              "L /opt/brother/scanner/brscan5 - - - - ${pkgs.brscan5}/opt/brother/scanner/brscan5"
            ] else []
          );

          # Brother's proprietary scanner drivers expect config files under
          # /etc/opt/brother/scanner/ — we create them declaratively since the
          # bundled brsaneconfigN tools can't write to /etc/opt on NixOS.
          environment.etc = lib.mkIf cfg.enableScanner {
            "sane.d/brother4.conf" = lib.mkIf (cfg.scannerBackend == "brscan4") {
              text = ''
                net Brother_MFC-9970CDW ${cfg.ipAddress}
              '';
            };
            "opt/brother/scanner/brscan4/brsanenetdevice4.cfg" = lib.mkIf (cfg.scannerBackend == "brscan4") {
              text = ''
                DEV=eth,0,"Brother_MFC-9970CDW",${cfg.ipAddress},"MFC-9970CDW"
              '';
            };
            "sane.d/brother5.conf" = lib.mkIf (cfg.scannerBackend == "brscan5") {
              text = ''
                net Brother_MFC-9970CDW ${cfg.ipAddress}
              '';
            };
            "opt/brother/scanner/brscan5/brscan5.conf" = lib.mkIf (cfg.scannerBackend == "brscan5") {
              text = ''
                [Device]
                Model  = MFC-9970CDW
                Name   = Brother_MFC-9970CDW
                IP     = ${cfg.ipAddress}
                Node   = "/dev/usb/scanner0"
                Type   = 3
              '';
            };
          };
        };
      };
  };
}
