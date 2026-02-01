{
  dotfilesDir,
  ...
}:
let
  kanataConfigDir = "${dotfilesDir}/kanata";
in
{
  services.kanata = {
    enable = true;
    keyboards = {
      macbook = {
        configFile = "${kanataConfigDir}/macbook.kbd";
        port = 5829;
        vkAgent = {
          enable = true;
          blacklist = [
            "com.hnc.Discord"
            "com.openai.chat"
          ];
        };
      };
    };
  };
}
