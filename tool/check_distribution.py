#!/usr/bin/env python3
"""Check that the official builder cannot drop our required notices."""
from pathlib import Path
import sys
import tarfile

root = Path(__file__).resolve().parents[1]
notice = (root / "NOTICE").read_text() + "\n" + (root / "THIRD_PARTY_NOTICES.md").read_text()
readme = (root / "README.md").read_text()
assert "<!-- BEGIN DISTRIBUTION NOTICES -->\n" + notice + "<!-- END DISTRIBUTION NOTICES -->" in readme, "README notices are out of sync"
assert "Apache License" in (root / "LICENSE").read_text()
assert (root / "THIRD_PARTY_NOTICES").read_text() == notice, "Collector notices are out of sync"
for filename in sys.argv[1:]:
    with tarfile.open(filename) as archive:
        members = archive.getmembers()
        for member in members:
            path = Path(member.name)
            assert not path.is_absolute() and ".." not in path.parts, member.name
            assert path.name != ".DS_Store" and not path.name.startswith("._"), member.name
            assert not any(x in path.parts for x in (".dart_tool", ".dnkeys", "local.properties", "Pods")), member.name
        readmes = [m for m in members if Path(m.name).name == "README.md"]
        assert len(readmes) == 1, filename
        assert notice in archive.extractfile(readmes[0]).read().decode(), "Archive lost notices"
        assert any(Path(m.name).name == "LICENSE" for m in members), filename
        notices = [m for m in members if Path(m.name).name == "NOTICES"]
        assert len(notices) == 1, "Archive needs one collector-readable NOTICES file"
        assert archive.extractfile(notices[0]).read().decode() == notice, "Archive notices differ"
print("Distribution notices and supplied archives passed.")
