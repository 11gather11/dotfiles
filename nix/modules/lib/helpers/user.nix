{ config }:
let
  inherit (config.home) username;
  githubId = "160300516";
  email = "${githubId}+${username}@users.noreply.github.com";
in
{
  inherit username githubId email;
}
