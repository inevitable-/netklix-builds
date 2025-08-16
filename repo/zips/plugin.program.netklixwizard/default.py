import xbmc, xbmcgui, xbmcaddon, xbmcvfs
import os, zipfile, urllib.request, traceback

ADDON = xbmcaddon.Addon()
NAME  = ADDON.getAddonInfo('name')
HOME  = xbmcvfs.translatePath('special://home/')
TEMP  = xbmcvfs.translatePath('special://temp/')
ZIP_DL = os.path.join(TEMP, 'NetKlixLiteBuild.zip')

# Download URL for the big build
DOWNLOAD_URL = "https://github.com/inevitable-/netklix-builds/releases/download/v1.0.0/NetKlixLiteBuild.zip"

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
