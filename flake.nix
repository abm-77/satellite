{
  description = "satellite";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in with pkgs;
  {
    devShells.${system}.default = 
      pkgs.mkShell
        {
          shellHook = ''
            fish
          '';

          buildInputs = [
            clang
            zig
            zls
            dwarfdump
          ];

        };
  };
}
