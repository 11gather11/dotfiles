function nx -d "Run a command with nix shell packages"
    set -l pkgs
    while test (count $argv) -gt 0; and test "$argv[1]" != --
        if string match -q '*#*' -- $argv[1]
            set -a pkgs $argv[1]
        else
            set -a pkgs "nixpkgs#$argv[1]"
        end
        set argv $argv[2..]
    end
    test (count $argv) -gt 0; and test "$argv[1]" = --; and set argv $argv[2..]
    echo ">" nix shell $pkgs --command $argv >&2
    nix shell $pkgs --command $argv
end
