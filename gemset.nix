{
  asciidoctor = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1hbin3j8wynl2fpqa3d6vb932pyngyfn8j2q6gbbn1n23z7srqqn";
      type = "gem";
    };
    version = "2.0.26";
  };
  asciidoctor-revealjs = {
    dependencies = ["asciidoctor"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1qkapy8nck52r7aldmnrvaabzrmizwa9664ngziivjgjxbksa11m";
      type = "gem";
    };
    version = "5.2.0";
  };
}
