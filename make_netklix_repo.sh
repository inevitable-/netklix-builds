#!/usr/bin/env bash
set -euo pipefail

###
# CONFIG — change only if you bump versions or rename things
###
GITHUB_USER="inevitable-"
GITHUB_REPO="netklix-builds"

WIZ_ID="plugin.program.netklixwizard"
WIZ_NAME="NetKlix Wizard"
WIZ_VERSION="1.0.1"          # your wizard version (matches the zip name)
REPO_ID="repository.netklix"
REPO_NAME="NetKlix Repo"
REPO_VERSION="1.0.0"

# Release that contains the *big build* zip:
RELEASE_TAG="v1.0.0"
BUILD_ASSET="NetKlixLiteBuild.zip"

# Where to generate everything (your local repo working dir)
ROOT_DIR="${HOME}/Desktop/netklix-builds"

# Derived
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
DOWNLOAD_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${BUILD_ASSET}"

echo "==> Preparing structure at: ${ROOT_DIR}"
mkdir -p "${ROOT_DIR}/zips/${WIZ_ID}"
mkdir -p "${ROOT_DIR}/zips/${REPO_ID}"

#####################################
# 1) Write wizard addon.xml + default.py (in zips/<wizard>/)
#####################################
cat > "${ROOT_DIR}/zips/${WIZ_ID}/addon.xml" <<EOF
<addon id="${WIZ_ID}"
       name="${WIZ_NAME}"
       version="${WIZ_VERSION}"
       provider-name="${GITHUB_USER}">
  <requires>
    <import addon="xbmc.python" version="3.0.0"/>
  </requires>
  <extension point="xbmc.python.script" library="default.py" />
  <extension point="xbmc.addon.metadata">
    <summary>${WIZ_NAME}</summary>
    <description>Setup and install NetKlix Lite Build automatically.</description>
    <platform>all</platform>
  </extension>
</addon>
EOF

cat > "${ROOT_DIR}/zips/${WIZ_ID}/default.py" <<'PYEOF'
import xbmc, xbmcgui, xbmcaddon, xbmcvfs
import os, zipfile, urllib.request, traceback

ADDON = xbmcaddon.Addon()
NAME  = ADDON.getAddonInfo('name')
HOME  = xbmcvfs.translatePath('special://home/')
TEMP  = xbmcvfs.translatePath('special://temp/')
ZIP_DL = os.path.join(TEMP, 'NetKlixLiteBuild.zip')

# Download URL for the big build
DOWNLOAD_URL = "__DOWNLOAD_URL__"

def notify(msg, icon=xbmcgui.NOTIFICATION_INFO):
    xbmcgui.Dialog().notification(NAME, msg, icon, 5000)

def download(url, dest):
    dp = xbmcgui.DialogProgress(); dp.create(NAME, "Downloading build…")
    try:
        with urllib.request.urlopen(url) as r, open(dest, 'wb') as out:
            total = int(r.headers.get('Content-Length') or 0); got = 0
            while True:
                chunk = r.read(262144)
                if not chunk: break
                out.write(chunk); got += len(chunk)
                if total:
                    dp.update(int(got * 100.0 / total),
                              f"{got//1048576} / {total//1048576} MB")
                if dp.iscanceled():
                    dp.close(); return False
        dp.close(); return True
    except Exception as e:
        dp.close(); notify(f"Download failed: {e}", xbmcgui.NOTIFICATION_ERROR)
        xbmc.log(f"{NAME} download error: {e}\n{traceback.format_exc()}", xbmc.LOGERROR)
        return False

def extract(zip_path, target):
    dp = xbmcgui.DialogProgress(); dp.create(NAME, "Installing build…")
    try:
        with zipfile.ZipFile(zip_path, 'r') as z:
            names = z.namelist()
            tops = {n.split('/')[0] for n in names if '/' in n}
            if not ({'addons','userdata'} & tops):
                dp.close(); notify("Invalid build zip structure", xbmcgui.NOTIFICATION_ERROR); return False
            total = max(1, len(names))
            for i, m in enumerate(z.infolist(), 1):
                z.extract(m, target)
                if dp.iscanceled(): dp.close(); return False
                dp.update(int(i * 100.0 / total))
        dp.close(); return True
    except Exception as e:
        dp.close(); notify(f"Install failed: {e}", xbmcgui.NOTIFICATION_ERROR)
        xbmc.log(f"{NAME} extract error: {e}\n{traceback.format_exc()}", xbmc.LOGERROR)
        return False

def main():
    os.makedirs(TEMP, exist_ok=True)
    if not download(DOWNLOAD_URL, ZIP_DL): return
    if not extract(ZIP_DL, HOME): return
    try: os.remove(ZIP_DL)
    except: pass
    notify("Install complete — restarting…")
    xbmc.executebuiltin('RestartApp')

if __name__ == '__main__':
    main()
PYEOF

# Inject the actual URL
python3 - <<PY
p = "${ROOT_DIR}/zips/${WIZ_ID}/default.py"
with open(p, "r+", encoding="utf-8") as f:
    s = f.read().replace("__DOWNLOAD_URL__", "${DOWNLOAD_URL}")
    f.seek(0); f.truncate(); f.write(s)
print("Injected DOWNLOAD_URL into default.py")
PY

#####################################
# 2) Zip the wizard folder (clean Mac metadata)
#####################################
echo "==> Creating wizard zip…"
(
  cd "${ROOT_DIR}/zips"
  /usr/bin/zip -r "${WIZ_ID}-${WIZ_VERSION}.zip" "${WIZ_ID}" \
    -x "*/.DS_Store" -x "__MACOSX/*"
)
echo "Wizard zip: zips/${WIZ_ID}-${WIZ_VERSION}.zip"

#####################################
# 3) Repository addon.xml (zips/<repo>/addon.xml)
#####################################
cat > "${ROOT_DIR}/zips/${REPO_ID}/addon.xml" <<EOF
<addon id="${REPO_ID}"
       name="${REPO_NAME}"
       version="${REPO_VERSION}"
       provider-name="${GITHUB_USER}">
  <extension point="xbmc.addon.repository" name="${REPO_NAME}">
    <info compressed="false">${RAW_BASE}/addons.xml</info>
    <checksum>${RAW_BASE}/addons.xml.md5</checksum>
    <datadir zip="true">${RAW_BASE}/zips/</datadir>
  </extension>
  <extension point="xbmc.addon.metadata">
    <summary>${REPO_NAME}</summary>
    <description>Repository for the NetKlix Wizard.</description>
    <platform>all</platform>
  </extension>
</addon>
EOF

echo "==> Creating repository zip…"
(
  cd "${ROOT_DIR}/zips"
  /usr/bin/zip -r "${REPO_ID}-${REPO_VERSION}.zip" "${REPO_ID}" \
    -x "*/.DS_Store" -x "__MACOSX/*"
)
echo "Repo zip: zips/${REPO_ID}-${REPO_VERSION}.zip"

#####################################
# 4) Root addons.xml + MD5
#####################################
cat > "${ROOT_DIR}/addons.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<addons>
  <addon id="${WIZ_ID}"
         name="${WIZ_NAME}"
         version="${WIZ_VERSION}"
         provider-name="${GITHUB_USER}">
    <requires>
      <import addon="xbmc.python" version="3.0.0"/>
    </requires>
    <extension point="xbmc.python.script" library="default.py"/>
    <extension point="xbmc.addon.metadata">
      <summary>${WIZ_NAME}</summary>
      <description>Setup and install NetKlix Lite Build automatically.</description>
      <platform>all</platform>
    </extension>
  </addon>
</addons>
EOF

echo "==> Generating addons.xml.md5…"
if command -v md5 >/dev/null 2>&1; then
  (cd "${ROOT_DIR}" && md5 -r addons.xml | awk '{print $1}' > addons.xml.md5)
elif command -v md5sum >/dev/null 2>&1; then
  (cd "${ROOT_DIR}" && md5sum addons.xml | awk '{print $1}' > addons.xml.md5)
else
  echo "ERROR: md5/md5sum not found. Install coreutils or run 'md5' on macOS."
  exit 1
fi

#####################################
# 5) Summary
#####################################
echo
echo "==================== DONE ===================="
echo "Local outputs in: ${ROOT_DIR}"
echo "  - addons.xml"
echo "  - addons.xml.md5"
echo "  - zips/${WIZ_ID}/addon.xml"
echo "  - zips/${WIZ_ID}/default.py"
echo "  - zips/${WIZ_ID}-${WIZ_VERSION}.zip"
echo "  - zips/${REPO_ID}/addon.xml"
echo "  - zips/${REPO_ID}-${REPO_VERSION}.zip"
echo
echo "Upload/commit these files to GitHub:"
echo "  ${ROOT_DIR}/addons.xml"
echo "  ${ROOT_DIR}/addons.xml.md5"
echo "  ${ROOT_DIR}/zips/${WIZ_ID}-${WIZ_VERSION}.zip"
echo "  ${ROOT_DIR}/zips/${REPO_ID}-${REPO_VERSION}.zip"
echo
echo "Kodi repo URLs (used by repository add-on):"
echo "  Info:      ${RAW_BASE}/addons.xml"
echo "  Checksum:  ${RAW_BASE}/addons.xml.md5"
echo "  Datadir:   ${RAW_BASE}/zips/"
echo "Wizard will download build from:"
echo "  ${DOWNLOAD_URL}"