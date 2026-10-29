# Homebrew formula for hub, the gh-based rewrite of the classic `hub` git wrapper.
#
# This repository is its own tap; REPO below is its GitHub slug. Install with:
#
#   brew tap #{REPO} https://github.com/#{REPO}
#   brew install #{REPO}/hub
class Hub < Formula
  # Assumed GitHub slug of this project. It is spelled out only here, so change it here.
  REPO = "brc-dd/hub".freeze

  desc "Git wrapper that adds GitHub commands, built on the gh CLI"
  homepage "https://github.com/#{REPO}"
  # script/update-formula fills in url and sha256 for each vX.Y.Z tag. Until the first release
  # they are placeholders, so install the main branch instead: brew install --HEAD #{REPO}/hub
  url "https://github.com/#{REPO}/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "69c9a25e7def204c94979af955b93bdeb94223540201c3ade49805283d1c9f19"
  # TODO(license): no license has been chosen yet. Add `license "<SPDX id>"` here once there is one.
  head "https://github.com/#{REPO}.git", branch: "main"

  # git is not listed: Homebrew itself requires it.
  depends_on "bash"
  depends_on "gh"

  conflicts_with "hub", because: "both install a `hub` executable (this is the gh-based rewrite)"

  def install
    # bin/hub needs bash 5 (macOS's /bin/bash is 3.2), so run it with the brewed one.
    inreplace "bin/hub", "#!/usr/bin/env bash", "#!#{formula_opt_bin("bash")}/bash"
    # Keep bin/, lib/ and VERSION side by side: bin/hub follows the HOMEBREW_PREFIX/bin/hub
    # symlink back to prefix/bin/hub and loads prefix/lib/hub and prefix/VERSION from there.
    prefix.install "bin", "lib", "VERSION"

    zsh_completion.install "completions/hub.zsh" => "_hub" if File.exist?("completions/hub.zsh")
    bash_completion.install "completions/hub.bash" => "hub" if File.exist?("completions/hub.bash")
    fish_completion.install "completions/hub.fish" if File.exist?("completions/hub.fish")
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
