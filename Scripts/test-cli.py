#!/usr/bin/env python3
"""End-to-end check of the public CLI against a real MIDI file."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "Scripts" / "midiscore"
MIDI = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Samples" / "scale.mid"


def run(*args: object, succeeds: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(CLI), *(str(arg) for arg in args)],
                            capture_output=True, text=True, check=False)
    if (result.returncode == 0) != succeeds:
        raise AssertionError(f"{args}: {result.stdout}\n{result.stderr}")
    return result


with tempfile.TemporaryDirectory(prefix="midiscore-cli-test-") as folder:
    directory = Path(folder)
    imported = directory / "imported.mscore"
    edited = directory / "edited.mscore"
    final = directory / "final.mscore"

    run("import-midi", MIDI, "--out", imported)
    source = json.loads(imported.read_text())
    assert source["tracks"] and source["tracks"][0]["notes"]

    run("page", "set", imported, "--title", "Codex QA", "--key", "G",
        "--meter", "3/4", "--measure-spacing", "180", "--out", edited)
    run("chord", "set", edited, "--bar", 1, "--beat", 2,
        "--symbol", "Am", "--in-place")
    note_id = run("note", "add", edited, "--track", 1, "--pitch", "C4",
                  "--bar", 2, "--beat", 1, "--duration", 1,
                  "--lyric", "가", "--in-place").stdout.split("새 음표 ID: ")[1].strip()
    run("note", "set", edited, "--track", 1, "--id", note_id,
        "--pitch", "D4", "--lyric", "나", "--in-place")
    run("note", "set", edited, "--track", 1, "--id", note_id,
        "--lyric", "둘", "--verse", 2, "--in-place")
    run("note", "set", edited, "--track", 1, "--id", note_id,
        "--lyric", "넷", "--verse", 4, "--in-place")
    run("repeat", "add", edited, "--start-bar", 1, "--end-bar", 2,
        "--first-ending-bar", 2, "--second-ending-end-bar", 3, "--in-place")
    run("navigation", "add", edited, "--bar", 1, "--kind", "segno", "--in-place")
    run("navigation", "add", edited, "--bar", 3, "--kind", "to-coda", "--in-place")
    run("navigation", "add", edited, "--bar", 5, "--kind", "coda", "--in-place")
    run("navigation", "add", edited, "--bar", 4, "--kind", "ds-coda", "--in-place")
    run("quantize", edited, "--track", 1, "--grid", 8,
        "--ids", note_id, "--melody", "--in-place")
    run("track", "add", edited, "--name", "Strings", "--clef", "bass", "--out", final)

    viewed = json.loads(run("inspect", final, "--json", "--track", 1,
                            "--from-bar", 1, "--to-bar", 2, "--limit", 0).stdout)
    assert viewed["page"]["title"] == "Codex QA"
    assert viewed["page"]["measureWidthRatio"] == 1.8
    assert viewed["page"]["numerator"] == 3
    assert viewed["chords"][0]["symbol"] == "Am"
    note = next(note for note in viewed["tracks"][0]["notes"] if note["id"] == note_id)
    assert note["pitch"] == 62 and note["lyric"] == "나"
    assert note["lyrics"] == ["나", "둘", "", "넷"]
    assert viewed["repeats"][0]["endMeasure"] == 1
    assert viewed["playbackBars"][:8] == [1, 2, 1, 3, 4, 1, 3, 5]
    assert {mark["kind"] for mark in viewed["navigationMarks"]} == {
        "segno", "to-coda", "coda", "ds-coda"
    }
    assert len(json.loads(final.read_text())["tracks"]) == 2
    assert source["page"]["title"] != "Codex QA"

    midi_output = directory / "edited.mid"
    run("export-midi", final, "--track", 1, "--out", midi_output)
    assert midi_output.read_bytes().startswith(b"MThd")
    run("page", "set", final, "--title", "not saved", "--out", final,
        succeeds=False)
    run("note", "add", final, "--track", 1, "--pitch", "H4",
        "--bar", 1, "--beat", 1, "--duration", 1,
        "--out", directory / "invalid.mscore", succeeds=False)
    assert not (directory / "invalid.mscore").exists()
    run("repeat", "add", final, "--start-bar", 2, "--end-bar", 4,
        "--out", directory / "overlap.mscore", succeeds=False)
    assert not (directory / "overlap.mscore").exists()
    run("repeat", "remove", final, "--start-bar", 1, "--in-place")
    assert not json.loads(run("inspect", final, "--json").stdout)["repeats"]
    run("navigation", "remove", final, "--kind", "segno",
        "--out", directory / "broken.mscore", succeeds=False)
    assert not (directory / "broken.mscore").exists()
    run("navigation", "remove", final, "--kind", "ds-coda", "--in-place")
    run("navigation", "remove", final, "--kind", "segno", "--in-place")
    assert "segno" not in {mark["kind"] for mark in
                           json.loads(run("inspect", final, "--json").stdout)["navigationMarks"]}

print(f"CLI 통합 검사 통과: {MIDI}")
