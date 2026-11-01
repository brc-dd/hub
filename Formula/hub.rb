class Hub < Formula
  REPO = "brc-dd/hub".freeze

  desc "Git wrapper that adds GitHub commands, built on the gh CLI"
  homepage "https://github.com/#{REPO}"
  url "https://github.com/#{REPO}/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "bf64a2d0304f0094c5a3d773eceabdb3e79d4d651dfb8b270fe9a60a653e1284"
  license "MIT"
  head "https://github.com/#{REPO}.git", branch: "main"

  depends_on "bash"
  depends_on "gh"

  conflicts_with "hub", because: "both install a `hub` executable"

  def install
    inreplace "bin/hub", "#!/usr/bin/env bash", "#!#{Formula["bash"].opt_bin}/bash"
    prefix.install "bin", "lib", "VERSION"
    bash_completion.install "completions/hub.bash" => "hub"
    zsh_completion.install "completions/hub.zsh" => "_hub"
    fish_completion.install "completions/hub.fish"
  end

  def caveats
    <<~EOS
      To make git run hub, add the line for your shell to its startup file:
        ~/.zshrc:                     eval "$(hub alias -s zsh)"
        ~/.bashrc:                    eval "$(hub alias -s bash)"
        ~/.config/fish/config.fish:   hub alias -s fish | source
    EOS
  end

  test do
    assert_match (prefix/"VERSION").read.strip, shell_output("#{bin}/hub --version")
    assert_match "git status", shell_output("#{bin}/hub --noop status")
  end
end
