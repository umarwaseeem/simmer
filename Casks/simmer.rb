# Homebrew cask for Simmer. The canonical copy lives in this repo; scripts/release.sh fills in
# `version` and `sha256`. Install it by tapping this repository directly:
#   brew tap umarwaseeem/simmer https://github.com/umarwaseeem/simmer && brew install --cask simmer
cask "simmer" do
  version "1.1.0"
  sha256 "56969e38749f98b841300f7a3d8ec6f2994c53bed90b3c6d81d941d19e605a16"

  url "https://github.com/umarwaseeem/simmer/releases/download/v#{version}/Simmer-#{version}.dmg"
  name "Simmer"
  desc "Battery charge limiter and battery insights for the menu bar"
  homepage "https://github.com/umarwaseeem/simmer"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Simmer.app"

  uninstall_preflight do
    # Restore default charging before the helper goes away (the helper resets the SMC keys).
    helper = "/Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper"
    system_command helper, args: ["--reset"], sudo: true if File.exist?(helper)
  end

  uninstall launchctl: "com.umarwaseem.simmer.helper",
            quit:      "com.umarwaseem.simmer",
            delete:    [
              "/Library/LaunchDaemons/com.umarwaseem.simmer.helper.plist",
              "/Library/PrivilegedHelperTools/com.umarwaseem.simmer.helper",
              "/usr/local/bin/simmerctl",
            ]

  zap trash: [
    "/Library/Application Support/Simmer",
    "/Library/Logs/simmerd.log",
    "~/Library/Application Support/Simmer",
    "~/Library/Caches/com.umarwaseem.simmer",
    "~/Library/Containers/com.umarwaseem.simmer.widget",
    "~/Library/Group Containers/*.com.umarwaseem.simmer",
    "~/Library/HTTPStorages/com.umarwaseem.simmer",
    "~/Library/Preferences/com.umarwaseem.simmer.plist",
  ]

  caveats <<~EOS
    Simmer is ad-hoc signed (no Apple Developer ID), so macOS blocks the first launch.
    Open it once with right-click > Open, or run:
      xattr -dr com.apple.quarantine "#{appdir}/Simmer.app"

    On first launch Simmer asks for your administrator password to install its
    charging helper (a LaunchDaemon). Only the helper can write the SMC charging keys.
  EOS
end
