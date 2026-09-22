# Diagnostics for Japanese prose: whether it reads naturally, and where it does
# not. Deterministic — the same text always produces the same findings — which
# is what makes it usable from a hook rather than as a second opinion.
#
# Most of the Japanese here and in the repositories worked on beside it is
# written by an agent: ADRs, design notes, the instruction files in this
# repository. This is the check on that.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  unzip,
}:

let
  # build.rs downloads SudachiDict and refuses any other copy of it: the
  # dictionary is pinned by SHA-256 so that the same input keeps producing the
  # same findings. The sandbox has no network, so the zip is fetched here and
  # handed over through the variable build.rs looks at first.
  #
  # The URL and both hashes are build.rs' own constants. Moving suiko's version
  # means reading them again — DICT_ZIP_URL and DICT_ZIP_SHA256 — because a
  # mismatch is a build failure, by design.
  sudachiDict = fetchurl {
    url = "https://d2ej7fkh96fzlu.cloudfront.net/sudachidict/sudachi-dictionary-20260723-core.zip";
    hash = "sha256-tug19jRA+XR0wtpF2AlQ9zdG5jLkC7/BaLQEFykTXh8=";
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "suiko";
  version = "0.3.8";

  src = fetchFromGitHub {
    owner = "nwiizo";
    repo = "suiko";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XffklNYFMRGfO6iRdajKi5BF/uBxWprfqf0H8DAhvEs=";
  };

  cargoHash = "sha256-udMpdjjywJIELbcKG4qfPfpR5Wda+igKUgHpe7lBohk=";

  nativeBuildInputs = [ unzip ];

  preBuild = ''
    unzip -j -o ${sudachiDict} '*system_core.dic' -d dict
    export SUIKO_SUDACHI_DICT=$PWD/dict/system_core.dic
  '';

  meta = {
    description = "Deterministic diagnostics for natural and readable Japanese writing";
    homepage = "https://github.com/nwiizo/suiko";
    mainProgram = "suiko";
    platforms = lib.platforms.unix;
  };
})
