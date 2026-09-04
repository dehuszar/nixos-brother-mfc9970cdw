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
        };
      };
  };
}
