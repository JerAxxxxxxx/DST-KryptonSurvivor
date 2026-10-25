"""Exercise release-asset failures in temporary, game-independent copies.

Only owned project assets are copied. Corruptions affect the temporary release
tree, never the source artwork or compiled mod in the working directory.
"""
from pathlib import Path
import importlib.util
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def rewrite_archive(path, mutate):
    with zipfile.ZipFile(path) as archive:
        entries = [(item, archive.read(item.filename)) for item in archive.infolist()]
    with zipfile.ZipFile(path, "w") as archive:
        for item, data in entries:
            archive.writestr(item, mutate(item.filename, data))


def symbol_record_offsets(data):
    """Locate BILD v6 records without regenerating sprites or texture data."""
    magic, version, symbol_count, _ = struct.unpack_from("<4sIII", data)
    assert (magic, version) == (b"BILD", 6)
    offset = 16

    def skip_string(position):
        return position + 4 + struct.unpack_from("<I", data, position)[0]

    offset = skip_string(offset)
    texture_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    for _ in range(texture_count):
        offset = skip_string(offset)
    records = []
    for _ in range(symbol_count):
        start = offset
        _, frames = struct.unpack_from("<II", data, offset)
        offset += 8 + frames * struct.calcsize("<II4fII")
        records.append((start, offset))
    return records


class AssetValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Keep temporary writes inside the ignored workspace output directory;
        # the copied release itself contains no build directory or local state.
        cls.temporary_parent = ROOT / "build/asset-validation"
        cls.temporary_parent.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="release-", dir=cls.temporary_parent)
        cls.temporary_root = Path(cls.temporary.name).resolve()
        # TemporaryDirectory owns cleanup; verify its absolute cleanup boundary.
        assert cls.temporary_root.is_relative_to(cls.temporary_parent.resolve())
        cls.clean_root = cls.temporary_root / "clean-release"
        cls.clean_root.mkdir()
        for name in ("mod", "assets"):
            shutil.copytree(ROOT / name, cls.clean_root / name)
        (cls.clean_root / "tools").mkdir()
        for name in ("check_assets.py", "klei_assets.py", "paths.py"):
            shutil.copy2(ROOT / "tools" / name, cls.clean_root / "tools" / name)
        # Run checks with Python's site-packages disabled. Copy only Pillow and
        # its bundled native libraries, so an installed NumPy/OpenCV or another
        # workspace cannot accidentally satisfy an undeclared dependency.
        cls.minimal_site = cls.temporary_root / "pillow-only"
        cls.minimal_site.mkdir()
        pillow_spec = importlib.util.find_spec("PIL")
        assert pillow_spec is not None, "Install requirements-check.txt first"
        pillow = Path(pillow_spec.origin).parent
        shutil.copytree(pillow, cls.minimal_site / "PIL")
        for sibling in pillow.parent.iterdir():
            if sibling.is_dir() and sibling.name.lower() == "pillow.libs":
                shutil.copytree(sibling, cls.minimal_site / sibling.name)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.release = self.temporary_root / self._testMethodName
        shutil.copytree(self.clean_root, self.release)

    def run_check(self):
        environment = os.environ.copy()
        environment["DST_GAME_DIR"] = str(self.temporary_root / "game-is-not-installed")
        environment["PYTHONPATH"] = ""
        bootstrap = (
            "import runpy,sys; "
            "sys.path[:0]=[sys.argv[1],sys.argv[2]]; "
            "runpy.run_path(sys.argv[3],run_name='__main__')"
        )
        return subprocess.run(
            [sys.executable, "-S", "-c", bootstrap, str(self.minimal_site),
             str(self.release / "tools"), str(self.release / "tools/check_assets.py")],
            cwd=self.release, env=environment, capture_output=True, text=True,
            encoding="utf8", errors="replace", check=False,
        )

    def rejected(self, reason):
        result = self.run_check()
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, "Corrupted release was accepted:\n" + output)
        self.assertIn(reason, output)

    def test_clean_release_needs_no_game_or_build_folder(self):
        for name in ("build", "user-pic", "node_modules", "archive"):
            self.assertFalse((self.release / name).exists())
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Validated", result.stdout)

    def test_missing_prefab_atlas(self):
        (self.release / "mod/images/inventoryimages/krypton_staff.xml").unlink()
        self.rejected("Missing declared local asset")

    def test_missing_mod_icon_metadata(self):
        path = self.release / "mod/modinfo.lua"
        path.write_text(re.sub(r'(?m)^icon(?:_atlas)?\s*=.*$', '',
                               path.read_text(encoding="utf8")), encoding="utf8")
        self.rejected("Missing or duplicate frontend mod icon field")

    def test_missing_mod_icon_atlas(self):
        (self.release / "mod/modicon.xml").unlink()
        self.rejected("Missing declared local asset")

    def test_mod_icon_path_casing_matches_linux(self):
        path = self.release / "mod/modinfo.lua"
        path.write_text(path.read_text(encoding="utf8").replace(
            'icon_atlas = "modicon.xml"', 'icon_atlas = "Modicon.xml"'), encoding="utf8")
        self.rejected("Missing declared local asset")

    def test_mod_icon_element_matches_metadata(self):
        path = self.release / "mod/modicon.xml"
        path.write_text(path.read_text(encoding="utf8").replace(
            '<Element name="modicon.tex"', '<Element name="unrelated.tex"'), encoding="utf8")
        self.rejected("Missing frontend mod icon atlas element")

    def test_missing_owned_animation_reference(self):
        (self.release / "mod/scripts/missing_asset_fixture.lua").write_text(
            'local assets = { Asset("ANIM", "anim/krypton_missing_for_test.zip") }\n',
            encoding="utf8",
        )
        self.rejected("Missing declared local asset")

    def test_asset_path_casing_matches_linux(self):
        (self.release / "mod/scripts/casing_fixture.lua").write_text(
            'local assets = { Asset("ANIM", "anim/Krypton_frostbreath_head.zip") }\n',
            encoding="utf8",
        )
        self.rejected("Missing declared local asset")

    def test_native_animation_is_not_distributed(self):
        # A project-owned archive is used as the stand-in; no native bytes are
        # read or redistributed even when testing a forbidden native filename.
        shutil.copy2(self.release / "mod/anim/krypton_staff_build.zip",
                     self.release / "mod/anim/cane.zip")
        self.rejected("Native runtime asset must not be distributed")

    def test_unreviewed_animation_archive_is_rejected(self):
        shutil.copy2(self.release / "mod/anim/krypton_staff_build.zip",
                     self.release / "mod/anim/unreviewed.zip")
        self.rejected("Unexpected distributed animation archive")

    def test_profile_head_frame_must_resolve(self):
        def remove_profile_frames(name, data):
            if name != "build.bin":
                return data
            modified = bytearray(data)
            for start, _ in symbol_record_offsets(data):
                # Every override retains the native head frame request. With
                # duration=1 the original game-visible side-frame bug returns.
                struct.pack_into("<I", modified, start + 8 + 4, 1)
            return bytes(modified)

        rewrite_archive(self.release / "mod/anim/krypton_frostbreath_head.zip",
                        remove_profile_frames)
        self.rejected("cannot resolve native head frame 1")

    def test_compiled_symbol_order_must_match_native_lookup(self):
        def reverse_symbols(name, data):
            if name != "build.bin":
                return data
            records = symbol_record_offsets(data)
            self.assertEqual(len(records), 2)
            first, second = records
            return data[:first[0]] + data[second[0]:second[1]] + data[first[0]:first[1]] + data[second[1]:]

        rewrite_archive(self.release / "mod/anim/krypton_frostbreath_head.zip", reverse_symbols)
        self.rejected("BILD symbols must be sorted by unsigned hash")

    def test_truncated_texture_payload(self):
        path = self.release / "mod/images/inventoryimages/krypton_staff.tex"
        path.write_bytes(path.read_bytes()[:-4])
        self.rejected("Texture data is truncated")

    def test_atlas_texture_reference_must_exist(self):
        path = self.release / "mod/images/inventoryimages/krypton_staff.xml"
        path.write_text(path.read_text(encoding="utf8").replace(
            'filename="krypton_staff.tex"', 'filename="missing_texture.tex"'), encoding="utf8")
        self.rejected("Missing atlas texture")

    def test_dark_suit_cannot_override_heads_or_hands(self):
        normal = self.release / "mod/anim/krypton_survivor.zip"
        target = self.release / "mod/anim/krypton_dark_suit.zip"
        with zipfile.ZipFile(normal) as archive:
            build = archive.read("build.bin")
            texture = archive.read("atlas-0.tex")
        old_size = struct.unpack_from("<I", build, 16)[0]
        name = b"krypton_dark_suit"
        build = build[:16] + struct.pack("<I", len(name)) + name + build[20 + old_size:]
        with zipfile.ZipFile(target, "w") as archive:
            archive.writestr("build.bin", build)
            archive.writestr("atlas-0.tex", texture)
        self.rejected("Dark suit must contain clothing symbols only")

    def test_dark_suit_geometry_matches_normal(self):
        def move_joint(name, data):
            if name != "build.bin":
                return data
            modified = bytearray(data)
            start, _ = symbol_record_offsets(data)[0]
            offset = start + 16  # First frame's x center.
            value = struct.unpack_from("<f", data, offset)[0]
            struct.pack_into("<f", modified, offset, value + 1)
            return bytes(modified)

        rewrite_archive(self.release / "mod/anim/krypton_dark_suit.zip", move_joint)
        self.rejected("Dark suit symbol geometry must match normal")

    def test_matching_normal_dark_waists_cannot_revert_to_wide_shorts(self):
        def widen_waist(name, data):
            if name != "build.bin":
                return data
            modified = bytearray(data)
            for start, _ in symbol_record_offsets(data):
                # SDBM hash of torso_pelvis; mutate both builds together so their
                # mutual geometry check alone cannot catch the old wide waist.
                if struct.unpack_from("<I", data, start)[0] == 3281870581:
                    struct.pack_into("<f", modified, start + 8 + 16, 76)
            return bytes(modified)

        for relative in ("krypton_survivor.zip", "krypton_dark_suit.zip"):
            rewrite_archive(self.release / "mod/anim" / relative, widen_waist)
        self.rejected("Waist width must match supplied suit placement")

    def test_dark_flight_needs_all_six_poses(self):
        def drop_last_pose(name, data):
            if name != "build.bin":
                return data
            modified = bytearray(data)
            start, _ = symbol_record_offsets(data)[0]
            offset = start + 8 + 5 * struct.calcsize("<II4fII")
            struct.pack_into("<I", modified, offset, 6)
            return bytes(modified)

        rewrite_archive(self.release / "mod/anim/krypton_dark_flight.zip", drop_last_pose)
        self.rejected("Dark flight must cover six poses")

    def test_dark_suit_does_not_bundle_animation(self):
        with zipfile.ZipFile(self.release / "mod/anim/krypton_flight.zip") as archive:
            owned_animation = archive.read("anim.bin")
        with zipfile.ZipFile(self.release / "mod/anim/krypton_dark_suit.zip", "a") as archive:
            archive.writestr("anim.bin", owned_animation)
        self.rejected("Dark suit packs must be build-only")


if __name__ == "__main__":
    unittest.main(verbosity=2)
