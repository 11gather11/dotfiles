{
  pin = {
    type = "github";
    owner = "mattpocock";
    repo = "skills";
    branch = "main";
  };

  # Pinned for the Claude Code plugin the repository ships as, which
  # agent-skills.nix links whole; no skill from it is selected here. The
  # source is still registered, so its skills are discovered, and the prefix
  # keeps its tdd from colliding with the local one in that catalog.
  # deprecated/ and in-progress/ also exist and are deliberately not read.
  subdir = "skills";
  idPrefix = "mattpocock";
}
