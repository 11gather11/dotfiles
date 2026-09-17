{
  pin = {
    type = "github";
    owner = "mattpocock";
    repo = "skills";
    branch = "main";
  };

  # deprecated/ and in-progress/ also exist in this repository and are
  # deliberately not read.
  subdir = "skills/productivity";
  # Namespaced, because registering the source at all makes every skill in it
  # visible and this one ships a tdd that collides with the local one.
  idPrefix = "mattpocock";
}
