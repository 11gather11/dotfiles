{
  pkgs,
  username,
  homedir,
  ...
}:
{
  # Set primary user for homebrew
  system.primaryUser = username;

  # Define user
  users.users.${username} = {
    home = homedir;
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;
  };

  # Add fish to system shells
  environment.shells = [ pkgs.fish ];
}
