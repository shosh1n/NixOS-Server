{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agenix.url = "github:ryantm/agenix";
    attic.url = "github:zhaofengli/attic";
  };

  outputs = { self, nixpkgs, agenix, attic, ...}@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      modules = [
        agenix.nixosModules.default ./configuration.nix attic.nixosModules.atticd
      ];
    };
  };
}
