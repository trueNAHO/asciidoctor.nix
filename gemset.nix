{
  asciidoctor = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "00612l3n4swjyv0i8kg673dhq289vgz1gswbscr0jcmas9lqq4q7";
      type = "gem";
    };
    version = "2.0.21";
  };
  asciidoctor-revealjs = {
    dependencies = ["asciidoctor"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0jgazcfzn577xlichfj0rvci0fayp63xcng11ss9mmwqgk48ri53";
      type = "gem";
    };
    version = "5.1.0";
  };
}
