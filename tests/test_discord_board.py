# tests/test_discord_board.py
"""Tests for tools/discord_board.py, the live leaderboard message.

    python3 tests/test_discord_board.py

Discord is a stub opener, so nothing goes online.
"""
# ------------------
import io
import json
import os
import sys
import unittest
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import discord_board as D  # noqa: E402
import leaderboard_ingest as L  # noqa: E402

HOOK = "https://discord.com/api/webhooks/123456789012345678/abcDEF_ghi-JKL"


def entry(name, points, owner, time=60, first="2026-11-07T00:00:00Z"):
    return {"name": name, "points": points, "earned": points // 5, "time": time, "saveId": "ABC123",
            "owner": owner, "first": first}


def board():
    b = L.empty_board()
    b["updated"] = "2026-11-10T10:11:24Z"
    b["games"]["red"]["entries"] = [entry("ASH", 50, "discord:a"), entry("GARY", 90, "discord:b"),
                                    entry("MISTY", 50, "discord:c", time=30), entry("BROCK", 10, "discord:d")]
    b["games"]["emerald"]["entries"] = [entry("@everyone *hi*", 5, "discord:a")]
    b["extra"]["crystal"]["entries"] = [dict(entry("ETHAN", 20, "online:e"), sources={})]
    return b


class Response(io.BytesIO):
    def __init__(self, status, body):
        super().__init__(json.dumps(body).encode())
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Stub:
    def __init__(self, status=200, body=None):
        self.calls, self.status, self.body = [], status, body or {"id": "111", "channel_id": "222"}

    def __call__(self, req, timeout=None):
        self.calls.append((req.get_method(), req.full_url, json.loads(req.data)))
        if self.status >= 400:
            raise urllib.error.HTTPError(req.full_url, self.status, "no", {}, io.BytesIO(b"Unknown Message"))
        return Response(self.status, self.body)


class Build(unittest.TestCase):
    def setUp(self):
        self.msg = D.build(board())

    def test_layout_fits_discord(self):
        embeds = self.msg["embeds"]
        self.assertEqual(len(embeds), 6)  # header, four generations, Extra Credit
        self.assertLessEqual(len(embeds), D.MAX_EMBEDS)
        self.assertLessEqual(D.size(self.msg), D.MAX_TOTAL)
        for e in embeds:
            self.assertLessEqual(len(e.get("fields", [])), 25)
        games = [f["name"] for e in embeds[1:5] for f in e["fields"]]
        self.assertEqual(len(games), len(L.GAMES))
        self.assertEqual(self.msg["allowed_mentions"], {"parse": []})

    def test_board_ranking(self):
        red = self.msg["embeds"][1]["fields"][0]
        self.assertEqual(red["name"], "Red")
        lines = red["value"].split("\n")
        self.assertEqual(len(lines), 3, "top 3 only")
        self.assertIn("GARY", lines[0])
        self.assertIn("MISTY", lines[1], "equal points: shorter time first")
        self.assertIn("ASH", lines[2])
        self.assertIn("*No scores yet*", self.msg["embeds"][1]["fields"][1]["value"])
        self.assertEqual(self.msg["embeds"][1]["footer"]["text"], "4 on the board")

    def test_header(self):
        head = self.msg["embeds"][0]["description"]
        self.assertIn("**5** trainers across **2** games", head)
        self.assertIn("<t:1794305484:R>", head)  # 2026-11-10T10:11:24Z

    def test_names_are_plain(self):
        em = self.msg["embeds"][3]["fields"][2]["value"]
        self.assertIn("@​everyone", em)
        self.assertIn("\\*hi\\*", em)

    def test_extra(self):
        extra = self.msg["embeds"][-1]
        self.assertEqual([f["name"] for f in extra["fields"]], ["Crystal"])
        self.assertTrue(extra["url"].endswith("#crystal/extra"))
        empty = D.build(L.empty_board())["embeds"][-1]
        self.assertIn("No Extra Credit yet", empty["description"])
        self.assertNotIn("Updated", D.build(L.empty_board())["embeds"][0]["description"])

    def test_full_board_still_fits(self):
        b = L.empty_board()
        long = "W" * L.NAME_MAX
        for g in L.GAMES:
            b["games"][g]["entries"] = [entry(long, 999 - i, f"discord:{g}{i}") for i in range(50)]
            b["extra"][g]["entries"] = [dict(entry(long, 99, f"discord:{g}"), sources={})] * 3
        self.assertLessEqual(D.size(D.build(b)), D.MAX_TOTAL)


class Webhook(unittest.TestCase):
    def setUp(self):
        self.env = dict(os.environ)
        for k in ("DISCORD_BOARD_WEBHOOK", "DISCORD_BOARD_MESSAGE", "DISCORD_BOARD_THREAD"):
            os.environ.pop(k, None)

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.env)

    def test_update_without_setup_does_nothing(self):
        stub = Stub()
        self.assertEqual(D.update(board(), stub), 0)
        self.assertEqual(stub.calls, [])

    def test_update_edits_the_message(self):
        os.environ.update(DISCORD_BOARD_WEBHOOK=HOOK, DISCORD_BOARD_MESSAGE="555", DISCORD_BOARD_THREAD="777")
        stub = Stub()
        self.assertEqual(D.update(board(), stub), 0)
        method, url, body = stub.calls[0]
        self.assertEqual((method, url), ("PATCH", HOOK + "/messages/555?thread_id=777"))
        self.assertEqual(len(body["embeds"]), 6)

    def test_update_failure_is_reported(self):
        os.environ.update(DISCORD_BOARD_WEBHOOK=HOOK, DISCORD_BOARD_MESSAGE="555")
        self.assertEqual(D.update(board(), Stub(status=404)), 1)

    def test_post_to_a_new_forum_post(self):
        os.environ.update(DISCORD_BOARD_WEBHOOK=HOOK)
        stub = Stub()
        got = D.post(board(), thread_name="Leaderboard", opener=stub)
        method, url, body = stub.calls[0]
        self.assertEqual((method, url), ("POST", HOOK + "?wait=true"))
        self.assertEqual(body["thread_name"], "Leaderboard")
        self.assertEqual(got["id"], "111")

    def test_post_into_a_thread(self):
        os.environ.update(DISCORD_BOARD_WEBHOOK=HOOK)
        stub = Stub()
        D.post(board(), thread_id="999", opener=stub)
        self.assertEqual(stub.calls[0][1], HOOK + "?wait=true&thread_id=999")
        self.assertNotIn("thread_name", stub.calls[0][2])

    def test_bad_settings_stop_early(self):
        os.environ.update(DISCORD_BOARD_WEBHOOK="https://example.com/hook")
        with self.assertRaises(SystemExit):
            D.update(board(), Stub())
        os.environ.update(DISCORD_BOARD_WEBHOOK=HOOK, DISCORD_BOARD_MESSAGE="55; rm")
        with self.assertRaises(SystemExit):
            D.update(board(), Stub())


if __name__ == "__main__":
    unittest.main()
