# Bundled icon packs

`build_icon_packs.py` converts two open-source icon packs into the compact
format in `android/app/src/main/assets/iconpacks/`, which
`IconPackStore.kt` reads. It keeps only the geometry: each shape becomes
absolute path data and a stroke/fill flag. Nothing else from the SVGs ends up
in the app.

| Pack | Source (pinned commit) | Licence | Bundled |
|---|---|---|---|
| Lawnicons | [LawnchairLauncher/lawnicons](https://github.com/LawnchairLauncher/lawnicons) `6a75594bd0553e35118beb02b655f87e3ebd956a` | Apache 2.0 (`LICENSE` copied next to the data) | All ~10,300 icons |
| Arcticons | [Arcticons-Team/Arcticons](https://github.com/Arcticons-Team/Arcticons) `4e0bf8a8c2e85372b0c2a3f8583fb58dee70b050` | Icons CC BY-SA 4.0 (`NOTICE` next to the data) | Only icons for packages in `arcticons_packages.txt` |

The app credits both packs on the Icons settings screen. The converted
Arcticons icons are a CC BY-SA adaptation (they are recoloured and resized),
so they stay under CC BY-SA 4.0.

## Updating

```bash
SRC=/tmp/iconpack-src && mkdir -p $SRC && cd $SRC
git clone --filter=blob:none --sparse https://github.com/LawnchairLauncher/lawnicons.git
(cd lawnicons && git sparse-checkout set svgs app/assets && git checkout <commit>)
git clone --filter=blob:none --sparse https://github.com/Arcticons-Team/Arcticons.git
(cd Arcticons && git sparse-checkout set --no-cone /icons/white/ /app/src/main/assets/appfilter.xml && git checkout <commit>)

cd ~/minimal_launcher
# Optional: refresh the Arcticons package list from the phone (read-only).
adb shell pm list packages | sed 's/^package://' | sort > tool/iconpacks/arcticons_packages.txt
python3 -I tool/iconpacks/build_icon_packs.py --lawnicons $SRC/lawnicons --arcticons $SRC/Arcticons \
    --arcticons-packages tool/iconpacks/arcticons_packages.txt
```

Before bundling a new commit, check what changed (`git log` in both checkouts)
and update the commit hashes above.

To bundle **all** of Arcticons (about 15,000 icons, roughly +5 MB on the APK),
leave out `--arcticons-packages`.
