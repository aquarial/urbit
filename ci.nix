/* 

Examples

  Perform the same evaluation that occurs on Hercules CI:

    $ NIX_PATH="" nix-instantiate ci.nix

*/

{ supportedSystems ? [ "x86_64-linux" "x86_64-darwin" ] }:

let

  ci = import ./nix/ci-lib.nix;
  pkgs = import ./nix/pkgs.nix { };

  # The key with google storage bucket write permission,
  # deployed to ci via nixops `deployment.keys."service-account.json"`.
  serviceAccountKey = builtins.readFile ("/var/run/keys/service-account.json");

  systems = pkgs.lib.filterAttrs (_: v: builtins.elem v supportedSystems) {
    linux = "x86_64-linux";
    darwin = "x86_64-darwin";
  };

in ci.dimensionWith "system" systems (systemName: system:

  let

    # Sources are expected to be a split-derivation containing "out" and "md5"
    # attributes.
    pushObject = name: extension: src:
      let md5 = builtins.readFile src.md5;
      in pkgs.local-lib.pushStorageObject {
        inherit serviceAccountKey md5;

        src = src.out;
        bucket = "tlon-us-terraform";
        object = "releases/${name}-${md5}.${extension}";
      };

    # Push a pill split-derivation containing "build" attribute with the
    # with the ".pill" file extension.
    pushPill = name: src: pushObject name "pill" src.build;

    # Instantiate shared and static libraries/executables for the specific system.
    sharedPackages = import ./default.nix { inherit system; crossSystem = null; withStatic = false; };
    # staticPackages = import ./default.nix {
    #   inherit system;

    #   withStatic = true;
    #   crossSystem =
    #     if pkgs.stdenv.isLinux
    #       then pkgs.lib.systems.examples.musl64
    #       else null;
    # };

    # releaseTarball = drv.makeReleaseTarball {
    #   name = "urbit-${system}";
    #   contents = {
    #     "urbit" = "${staticPackages.urbit}/bin/urbit";
    #     "urbit-worker" = "${staticPackages.urbit}/bin/urbit-worker";
    #     "urbit-king" =
    #       "${staticPackages.hs.urbit-king.components.exes.urbit-king}/bin/urbit-king";
    #   };
    # };
    
    # # Filter out attributes we don't want to recurse into for ci.
    # #
    # # We remove Haskell packages/projects and instead use the `haskellProject`
    # # function from above to force evaluation via `recurseIntoAttrs` and to better
    # # display the individual components instead of all the haskell-nix attributes.
    # extraPackages = {
    #   urbit = staticPackages.urbit;

    #   hs = ci.dimensionHaskell pkgs "haskell" staticPackages.hs;

    #   # Push the release tarball artefact to the remote storage bucket.
    #   tarball = pushObject "urbit-${system}" "tar.gz" releaseTarball;

    #   # Only push the pills if we're evaluating on a linux build agent.
    # } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
    #   ivory = pushPill "ivory" sharedPackages.ivory;
    #   brass = pushPill "brass" sharedPackages.brass;
    #   solid = pushPill "solid" sharedPackages.solid;

    #   ivory-ropsten = pushPill "ivory-ropsten" sharedPackages.ivory-ropsten;
    #   brass-ropsten = pushPill "brass-ropsten" sharedPackages.brass-ropsten;
    # };

    platformFilter = ci.platformFilterGeneric pkgs.lib system;

  in ci.filterAttrsOnlyRecursive pkgs.lib (_: v: platformFilter v) sharedPackages
      # (sharedPackages // extraPackages)
)