{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    mas

    # Switches the macOS input source from the command line. Neovim calls it to
    # drop out of kana when Space arrives as a full-width space; see
    # nvim/lua/config/keymaps.lua.
    macism
  ];
}
