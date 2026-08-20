# TUI file manager, for the two things the shell here does not cover: renaming
# a batch of files, and moving between two directories that are not ~/Downloads
# (which dlmv handles).
{
  programs.yazi = {
    enable = true;

    # Wraps yazi so the shell follows it out — quit in a directory and the
    # shell is left there. Without this it is a viewer you always cd back from.
    enableFishIntegration = true;
  };
}
