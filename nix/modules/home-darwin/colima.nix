{
  pkgs,
  ...
}:
{
  # colima wraps lima-full, qemu and krunkit into its own PATH, so the VM stack
  # needs no companion packages here
  home.packages = [ pkgs.colima ];
}
