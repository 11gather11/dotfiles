{ pkgs, ... }:
{
  # Font configuration
  fonts = {
    packages = with pkgs; [
      plemoljp-nf
    ];
  };

}
