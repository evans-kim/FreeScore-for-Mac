const owner = "evans-kim";
const repo = "FreeScore-for-Mac";
const releaseURL = `https://github.com/${owner}/${repo}/releases/latest`;

async function showLatestRelease() {
  try {
    const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" }
    });
    if (!response.ok) return;
    const release = await response.json();
    if (!/^v\d+\.\d+\.\d+$/.test(release.tag_name)) return;
    const asset = release.assets?.find(item => item.name === "FreeScore-for-Mac.zip");
    document.getElementById("version-badge").textContent = release.tag_name;
    document.getElementById("release-version").textContent = release.tag_name;
    document.getElementById("release-date").textContent = release.published_at
      ? `${new Intl.DateTimeFormat("ko-KR", { dateStyle: "long" }).format(new Date(release.published_at))} 공개`
      : "최신 버전";
    document.getElementById("release-link").href = release.html_url || releaseURL;
    if (asset) document.getElementById("download").href = asset.browser_download_url;
  } catch {
    // The stable /releases/latest/download URL remains available when the API is unreachable.
  }
}

showLatestRelease();
