{
  pin = {
    type = "github";
    owner = "cursor";
    repo = "plugins";
    branch = "main";
  };

  # Pinned for pstack's generated Claude Code plugin, which agent-skills.nix
  # links whole; no skill from it is selected here. The repository holds
  # Cursor's other plugins too, so subdir narrows discovery to pstack's tree,
  # and the prefix keeps its tdd and teach apart from the local ones and
  # mattpocock's in that catalog.
  subdir = "harness/pstack/claude-code/skills";
  idPrefix = "pstack";
}
