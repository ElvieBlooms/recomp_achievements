"""Tests for tools/leaderboard_ingest.py.   python3 tests/test_leaderboard.py

Lua/Python checksum parity is checked from the Lua side in tests/run.lua.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import leaderboard_ingest as L  # noqa: E402


def body(game="Red", name="ASH", points="120", earned="20", save="ABC123", code=None):
    if code is None:
        code = L.check_code(game.lower(), name, int(points), int(earned), save)
    return (f"### Game\n\n{game}\n\n### Trainer name\n\n{name}\n\n### Points\n\n{points}\n\n"
            f"### Achievements earned\n\n{earned}\n\n### Save ID\n\n{save}\n\n"
            f"### Check code\n\n{code}\n")


class Ingest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.board = os.path.join(self.dir, "docs", "leaderboard.json")
        self.reply = os.path.join(self.dir, "reply.md")

    def run_ingest(self, text, author="alice", issue=1, now="2026-10-29T00:00:00Z"):
        env = dict(os.environ, ISSUE_BODY=text, ISSUE_AUTHOR=author, ISSUE_NUMBER=str(issue))
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "leaderboard_ingest.py"),
                            "--board", self.board, "--reply", self.reply, "--now", now],
                           env=env, capture_output=True, text=True)
        with open(self.reply, encoding="utf-8") as f:
            return p.returncode, f.read()

    def entries(self, game="red"):
        with open(self.board, encoding="utf-8") as f:
            return json.load(f)["games"][game]["entries"]

    def test_known_vectors(self):
        self.assertEqual(L.check_code("red", "ASH", 120, 20, "ABC123"), "DHC0-HH32")
        self.assertEqual(L.check_code("yellow", "red ", 0, 0, "ZZZZZZ"), "1F4B-5EVD")

    def test_accepts_and_ranks(self):
        rc, reply = self.run_ingest(body())
        self.assertEqual(rc, 0, reply)
        self.assertIn("Added", reply)
        rc, _ = self.run_ingest(body(name="GARY", points="200", earned="30", save="ZZZ999"),
                                author="bob", issue=2)
        self.assertEqual(rc, 0)
        self.assertEqual([e["name"] for e in self.entries()], ["GARY", "ASH"])

    def test_lenient_typing(self):
        # lower case, no dash, O for 0, spaces around values, "Pokemon Red"
        code = L.check_code("red", "ASH", 120, 20, "ABC123").replace("-", "").lower().replace("0", "o")
        rc, reply = self.run_ingest(body(game="Pokemon Red", save="abc123", code=f"  {code} "))
        self.assertEqual(rc, 0, reply)

    def test_typo_is_rejected(self):
        b = body().replace("### Points\n\n120", "### Points\n\n210")
        rc, reply = self.run_ingest(b)
        self.assertEqual(rc, 1)
        self.assertIn("check code", reply)
        self.assertFalse(os.path.exists(self.board))

    def test_over_max_rejected(self):
        rc, reply = self.run_ingest(body(points="746", earned="93"))
        self.assertEqual(rc, 1)
        self.assertIn("745", reply)

    def test_bad_names(self):
        for name in ["", "A" * 13, "<b>x</b>"]:
            rc, _ = self.run_ingest(body(name=name or "_No response_"))
            self.assertEqual(rc, 1, name)

    def test_update_same_save(self):
        self.run_ingest(body())
        rc, reply = self.run_ingest(body(points="300", earned="40"), issue=1)
        self.assertEqual(rc, 0, reply)
        self.assertIn("Updated", reply)
        e = self.entries()
        self.assertEqual(len(e), 1)
        self.assertEqual(e[0]["points"], 300)

    def test_other_account_cannot_take_a_save_id(self):
        self.run_ingest(body())
        rc, reply = self.run_ingest(body(points="300", earned="40"), author="mallory", issue=9)
        self.assertEqual(rc, 1)
        self.assertIn("another", reply)
        self.assertEqual(self.entries()[0]["points"], 120)

    def test_same_save_id_in_two_games(self):
        self.run_ingest(body())
        rc, _ = self.run_ingest(body(game="Blue"))
        self.assertEqual(rc, 0)
        self.assertEqual(len(self.entries("blue")), 1)

    def test_broken_board_is_a_bug_not_a_rejection(self):
        os.makedirs(os.path.dirname(self.board))
        with open(self.board, "w") as f:
            f.write("{nope")
        rc, reply = self.run_ingest(body())
        self.assertEqual(rc, 2)
        self.assertIn("maintainer", reply)


if __name__ == "__main__":
    unittest.main()
