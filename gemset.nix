{
  asciidoctor = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1wyxgwmnz9bw377r3lba26b090hbsq9qnbw8575a1prpy83qh82j";
      type = "gem";
    };
    version = "2.0.23";
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
