// The public releases repository holds the signed, notarized app and its update feed (README → Repositories).
// Since 1.5.0 every release also carries Voice-Pipes.dmg, so this always downloads the newest installer.
export const DOWNLOAD_URL = 'https://github.com/brancusi/voice-tools-releases/releases/latest/download/Voice-Pipes.dmg';
export const RELEASES_URL = 'https://github.com/brancusi/voice-tools-releases/releases';
// The terminal installer, attached to every release since 1.6.2 (Tools/install.sh): the app, `vp` and the agent skill.
export const INSTALL_COMMAND =
  'curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash';
