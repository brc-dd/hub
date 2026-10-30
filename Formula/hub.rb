class Hub < Formula
  REPO = "brc-dd/hub".freeze

  desc "Git wrapper that adds GitHub commands, built on the gh CLI"
  homepage "https://github.com/#{REPO}"
  url "https://github.com/#{REPO}/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "69c9a25e7def204c94979af955b93bdeb94223540201c3ade49805283d1c9f19"
  license "MIT"
  # For changes not released yet: brew install --HEAD #{REPO}/hub
  head "https://github.com/#{REPO}.git", branch: "main"

  depends_on "bash"
  depends_on "gh"

  conflicts_with "hub", because: "both install a `hub` executable (this is the gh-based rewrite)"

  def install
    inreplace "bin/hub", "#!/usr/bin/env bash", "#!#{formula_opt_bin("bash")}/bash"
    prefix.install "bin", "lib", "VERSION"
    zsh_completion.install "completions/hub.zsh" => "_hub"
    bash_completion.install "completions/hub.bash" => "hub"
    fish_completion.install "completions/hub.fish"
  end

  def caveats
    <<~EOS
      To make `git` run hub, add this line to your shell's startup file (~/.zshrc, ~/.bashrc):
        eval "$(hub alias -s)"
      For fish, add this line to ~/.config/fish/config.fish instead:
        hub alias -s fish | source
    EOS
  end

  test do
    assert_match "hub version", shell_output("#{bin}/hub --version")
    assert_match "git status", shell_output("#{bin}/hub --noop status")
  end
end
