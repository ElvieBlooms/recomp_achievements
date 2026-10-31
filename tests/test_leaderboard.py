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


def body(game="Red", name="ASH", points="120", earned="20", save="ABC123", code=None, time=None):
    minutes = None if not time else int(time.split(":")[0]) * 60 + int(time.split(":")[1])
    if code is None:
        code = L.check_code(game.lower(), name, int(points), int(earned), save, minutes)
    return (f"### Game\n\n{game}\n\n### Trainer name\n\n{name}\n\n### Points\n\n{points}\n\n"
            f"### Achievements earned\n\n{earned}\n\n### Play time\n\n{time or '_No response_'}\n\n"
            f"### Save ID\n\n{save}\n\n### Check code\n\n{code}\n")


def discord_event(path, score, owner="ab" * 16, token="t" * 40):
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"action": "discord-score", "client_payload": {
            "score": score, "owner": owner, "app_id": "999888777666555444", "token": token}}, f)


def card(game="red", name="ASH", points=120, earned=20, save="ABC123", minutes=None):
    return {"game": game, "name": name, "points": str(points), "earned": str(earned),
            "save_id": save, "time": "" if minutes is None else f"{minutes // 60}:{minutes % 60:02d}",
            "code": L.check_code(game, name, points, earned, save, minutes)}


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
        for name in ["", "A" * 13, "<b>x</b>"]:  # noqa
            rc, _ = self.run_ingest(body(name=name or "_No response_"))
            self.assertEqual(rc, 1, name)

    def test_blocked_names_rejected(self):
        for name in ["FUCK", "F_U_U_CK", "5H1T", "A55", "C0CK", "xXdickXx"]:
            rc, reply = self.run_ingest(body(name=name))
            self.assertEqual(rc, 1, name)
            self.assertIn("can't be shown", reply)
            self.assertNotIn(name, reply)
        self.assertFalse(os.path.exists(self.board))

    def test_filter_catches_tricks(self):
        for name in ["SHIIIT", "ASSES", "KKK", "HELL", "N1GGA", "BUTTS"]:
            self.assertTrue(L.name_blocked(name), name)

    def test_filter_spares_ordinary_names(self):
        for name in ["ASH", "RED", "CLASS", "BASS", "HELLO", "SHELL", "PEACOCK", "GRAPE",
                     "SPICY", "SHOE", "RACCOON", "ASSUME", "BUTTON", "TORPEDO", "ESSEX",
                     "TITAN", "BROCK", "COCKY", "NIGEL", "SASSY", "PIKA!", "Gary\u2642",
                     "MISTY", "KOKO", "BUTCH"]:
            self.assertFalse(L.name_blocked(name), name)

    def test_blocklist_file_parses(self):
        lists = L.load_blocklist()
        self.assertIn("fuck", lists["contains"])
        self.assertIn("ass", lists["exact"])
        self.assertNotIn("ass", lists["contains"])

    def test_workflow_ignores_reports(self):
        with open(os.path.join(ROOT, ".github", "workflows", "leaderboard.yml")) as f:
            wf = f.read()
        self.assertIn("'score'", wf)
        self.assertIn("'[Score]'", wf)
        self.assertNotIn("report", wf.lower())

    def test_banned_save(self):
        self.run_ingest(body())
        with open(self.board, encoding="utf-8") as f:
            board = json.load(f)
        board["games"]["red"]["entries"] = []
        board["banned"] = ["red:ABC123"]
        with open(self.board, "w", encoding="utf-8") as f:
            json.dump(board, f)
        rc, reply = self.run_ingest(body(points="300", earned="40"))
        self.assertEqual(rc, 1)
        self.assertIn("removed", reply)
        rc, _ = self.run_ingest(body(game="Blue"))
        self.assertEqual(rc, 0, "same id in another game is separate")

    def run_event(self, event_path, now="2026-10-29T00:00:00Z"):
        env = {k: v for k, v in os.environ.items() if not k.startswith("ISSUE_")}
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "leaderboard_ingest.py"),
                            "--event", event_path, "--board", self.board, "--reply", self.reply,
                            "--now", now], env=env, capture_output=True, text=True)
        with open(self.reply, encoding="utf-8") as f:
            return p.returncode, f.read()

    def test_issue_event_file(self):
        ev = os.path.join(self.dir, "ev.json")
        with open(ev, "w") as f:
            json.dump({"action": "opened", "issue": {"number": 5, "body": body(),
                                                    "user": {"login": "Alice"}}}, f)
        rc, reply = self.run_event(ev)
        self.assertEqual(rc, 0, reply)
        e = self.entries()[0]
        self.assertEqual((e["github"], e["issue"], e["owner"], e["via"]), ("Alice", 5, "gh:alice", "github"))
        self.assertIn("edit this issue", reply)

    def test_discord_event(self):
        ev = os.path.join(self.dir, "ev.json")
        discord_event(ev, card())
        rc, reply = self.run_event(ev)
        self.assertEqual(rc, 0, reply)
        self.assertIn("/score", reply)
        # same Discord account updates; a different one can't take the save
        discord_event(ev, card(points=300, earned=40))
        self.assertEqual(self.run_event(ev)[0], 0)
        discord_event(ev, card(points=400, earned=50), owner="cd" * 16)
        rc, reply = self.run_event(ev)
        self.assertEqual(rc, 1)
        self.assertIn("another account", reply)
        self.assertEqual(self.entries()[0]["points"], 300)

    def test_discord_and_github_dont_share_a_save(self):
        self.run_ingest(body())
        ev = os.path.join(self.dir, "ev.json")
        discord_event(ev, card(points=300, earned=40))
        rc, reply = self.run_event(ev)
        self.assertEqual(rc, 1)
        self.assertIn("another account", reply)

    def test_discord_checks_match_issue_checks(self):
        ev = os.path.join(self.dir, "ev.json")
        for score, why in [(card(name="5H1T"), "can't be shown"),
                           (dict(card(), points="746"), "745"),
                           (dict(card(), code="AAAA-AAAA"), "check code")]:
            discord_event(ev, score)
            rc, reply = self.run_event(ev)
            self.assertEqual(rc, 1, score)
            self.assertIn(why, reply)

    def test_discord_event_needs_owner(self):
        ev = os.path.join(self.dir, "ev.json")
        discord_event(ev, card(), owner="")
        self.assertEqual(self.run_event(ev)[0], 1)

    def test_old_entries_without_owner_still_belong_to_their_github_user(self):
        self.run_ingest(body())
        with open(self.board, encoding="utf-8") as f:
            board = json.load(f)
        del board["games"]["red"]["entries"][0]["owner"]
        with open(self.board, "w", encoding="utf-8") as f:
            json.dump(board, f)
        self.assertEqual(self.run_ingest(body(points="300", earned="40"), author="ALICE")[0], 0)
        self.assertEqual(self.run_ingest(body(points="400", earned="50"), author="bob")[0], 1)

    def test_game_limits_match_catalogs(self):
        import re as _re
        for game, info in L.GAMES.items():
            path = os.path.join(ROOT, "recomp_achievements", "catalog", game + ".lua")
            text = open(path, encoding="utf-8").read()
            pts = [int(x) for x in _re.findall(r"points = (\d+),", text)]
            self.assertEqual((sum(pts), len(pts)), (info["maxPoints"], info["total"]), game)

    def test_gen2_submission(self):
        rc, reply = self.run_ingest(body(game="Crystal", points="100", earned="12", time="20:00"))
        self.assertEqual(rc, 0, reply)
        self.assertIn("Pokemon Crystal", reply)
        rc, reply = self.run_ingest(body(game="Gold", points="686", earned="72"), author="bob")
        self.assertEqual(rc, 1)
        self.assertIn("685", reply)

    def test_v2_vectors(self):
        self.assertEqual(L.check_code("red", "ASH", 745, 93, "ABC123", 754), "K8ZM-8GYP")
        self.assertEqual(L.check_code("red", "ASH", 745, 93, "ABC123", 0), "ESH4-99C6")
        self.assertEqual(L.check_code("red", "ASH", 745, 93, "ABC123"),
                         L.check_code("red", "ASH", 745, 93, "ABC123", None))

    def test_play_time_is_stored_and_checked(self):
        rc, reply = self.run_ingest(body(time="12:34"))
        self.assertEqual(rc, 0, reply)
        self.assertIn("12:34", reply)
        self.assertEqual(self.entries()[0]["time"], 754)
        # a typo in the time breaks the code
        b = body(time="12:34").replace("12:34", "12:43")
        rc, reply = self.run_ingest(b, author="alice")
        self.assertEqual(rc, 1)
        self.assertIn("check code", reply)

    def test_time_formats(self):
        self.assertEqual(L.parse_time("12:34"), 754)
        self.assertEqual(L.parse_time(" 0:05 "), 5)
        self.assertEqual(L.parse_time("12h34m"), 754)
        self.assertIsNone(L.parse_time(""))
        for bad in ["12:60", "abc", "1234", "12:3"]:
            with self.assertRaises(L.Rejected, msg=bad):
                L.parse_time(bad)

    def test_save_id_o_is_zero(self):
        b = body(save="3N0S2H").replace("### Save ID\n\n3N0S2H", "### Save ID\n\n3nOs2h")
        rc, reply = self.run_ingest(b)
        self.assertEqual(rc, 0, reply)
        self.assertEqual(self.entries()[0]["saveId"], "3N0S2H")

    def test_old_cards_without_time_still_work(self):
        rc, reply = self.run_ingest(body())  # v1 code, no TIME line
        self.assertEqual(rc, 0, reply)
        self.assertIsNone(self.entries()[0]["time"])

    def test_equal_points_rank_by_shorter_time(self):
        for i, (name, time, save) in enumerate([("SLOW", "40:00", "AAAAAA"), ("NOTIME", None, "BBBBBB"),
                                                ("FAST", "25:10", "CCCCCC"), ("MID", "30:00", "DDDDDD")]):
            rc, reply = self.run_ingest(body(name=name, points="745", earned="93", save=save, time=time),
                                        author=f"u{i}", now=f"2026-10-29T00:00:0{i}Z")
            self.assertEqual(rc, 0, reply)
        self.run_ingest(body(name="MORE", points="500", earned="60", save="EEEEEE", time="1:00"),
                        author="u9")
        self.assertEqual([e["name"] for e in self.entries()], ["FAST", "MID", "SLOW", "NOTIME", "MORE"])

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


EXTRA = [("bonus", 3, 9, 20), ("naviplay", 12, 25, 85)]


def extra_body(game="Ruby", name="MAY", save="ABC123", lines=None, code=None, sources=EXTRA):
    if lines is None:
        lines = "\n".join(f"{i} {e}/{t} {p}" for i, e, t, p in sources)
    if code is None:
        code = L.extra_check_code(game.lower(), name, save, sources)
    return (f"### Game\n\n{game}\n\n### Trainer name\n\n{name}\n\n### Save ID\n\n{save}\n\n"
            f"### Extra credit lines\n\n{lines}\n\n### Extra code\n\n{code}\n")


class ExtraCredit(unittest.TestCase):
    setUp, run_ingest, run_event, entries = Ingest.setUp, Ingest.run_ingest, Ingest.run_event, Ingest.entries

    def extra(self, game="ruby"):
        with open(self.board, encoding="utf-8") as f:
            return json.load(f)["extra"][game]["entries"]

    def test_vector_matches_lua_and_js(self):
        self.assertEqual(L.extra_check_code("red", "ash", "abc123", [("naviplay", 12, 25, 85), ("bonus", 3, 9, 20)]),
                         "G519-TP8B")

    def test_issue_added_and_ranked(self):
        rc, reply = self.run_ingest(extra_body())
        self.assertEqual(rc, 0, reply)
        self.assertIn("Extra Credit", reply)
        e = self.extra()[0]
        self.assertEqual((e["points"], e["earned"]), (105, 15))
        self.assertEqual(e["sources"]["naviplay"], {"earned": 12, "total": 25, "points": 85})
        # a second player with fewer points goes below; the main board is untouched
        src = [("bonus", 9, 9, 50)]
        rc, _ = self.run_ingest(extra_body(name="BRENDAN", save="ZZZ999", sources=src), author="bob", issue=2)
        self.assertEqual(rc, 0)
        self.assertEqual([x["name"] for x in self.extra()], ["MAY", "BRENDAN"])
        self.assertEqual(self.entries("ruby"), [])

    def test_lines_can_be_comma_separated_on_one_line(self):
        rc, reply = self.run_ingest(extra_body(lines="bonus 3/9 20, NaviPlay 12 / 25 85pts"))
        self.assertEqual(rc, 0, reply)

    def test_typo_and_impossible_lines(self):
        rc, reply = self.run_ingest(extra_body(lines="bonus 3/9 21"))
        self.assertEqual(rc, 1)
        self.assertIn("extra code", reply)
        bad = [("bonus", 3, 9, 301)]
        rc, reply = self.run_ingest(extra_body(sources=bad))
        self.assertEqual(rc, 1)
        self.assertIn("can't come from", reply)
        rc, reply = self.run_ingest(extra_body(lines="hello there"))
        self.assertEqual(rc, 1)
        self.assertIn("isn't a line", reply)

    def test_owner_and_update(self):
        self.assertEqual(self.run_ingest(extra_body())[0], 0)
        more = [("bonus", 9, 9, 50), ("naviplay", 12, 25, 85)]
        self.assertEqual(self.run_ingest(extra_body(sources=more), issue=3)[0], 0)
        self.assertEqual(self.extra()[0]["points"], 135)
        rc, reply = self.run_ingest(extra_body(sources=more), author="mallory", issue=4)
        self.assertEqual(rc, 1)
        self.assertIn("another account", reply)

    def test_discord_extra_event(self):
        ev = os.path.join(self.dir, "ev.json")
        lines = "bonus 3/9 20, naviplay 12/25 85"
        with open(ev, "w", encoding="utf-8") as f:
            json.dump({"action": "discord-extra", "client_payload": {
                "extra": {"game": "ruby", "name": "MAY", "save_id": "ABC123", "extra": lines,
                          "code": L.extra_check_code("ruby", "MAY", "ABC123", EXTRA)},
                "owner": "ab" * 16, "app_id": "1", "token": "t" * 40}}, f)
        rc, reply = self.run_event(ev)
        self.assertEqual(rc, 0, reply)
        self.assertIn("/extra", reply)
        self.assertEqual(self.extra()[0]["via"], "discord")

    def test_workflow_and_form(self):
        with open(os.path.join(ROOT, ".github", "workflows", "leaderboard.yml")) as f:
            wf = f.read()
        self.assertIn("discord-extra", wf)
        self.assertIn("'[Extra]'", wf)
        with open(os.path.join(ROOT, ".github", "ISSUE_TEMPLATE", "extra.yml")) as f:
            form = f.read()
        for label in L.EXTRA_FIELDS.values():
            self.assertIn(f"label: {label}", form)


class DiscordReply(unittest.TestCase):
    """tools/discord_reply.py against a fake Discord API."""

    def test_edits_the_original_message(self):
        import http.server
        import threading
        got = {}

        class Fake(http.server.BaseHTTPRequestHandler):
            def do_PATCH(self):
                got["path"] = self.path
                got["body"] = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"{}")

            def log_message(self, *a):
                pass

        srv = http.server.HTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=srv.handle_request, daemon=True).start()
        d = tempfile.mkdtemp()
        ev, reply = os.path.join(d, "ev.json"), os.path.join(d, "r.md")
        discord_event(ev, card(), token="tok_" + "x" * 30)
        with open(reply, "w") as f:
            f.write("Added: **ASH** @everyone\n")
        env = dict(os.environ, DISCORD_API=f"http://127.0.0.1:{srv.server_port}/api/v10")
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "discord_reply.py"),
                            "--event", ev, "--reply", reply], env=env, capture_output=True, text=True)
        srv.server_close()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(got["path"], "/api/v10/webhooks/999888777666555444/tok_" + "x" * 30 + "/messages/@original")
        self.assertIn("ASH", got["body"]["content"])
        self.assertEqual(got["body"]["allowed_mentions"], {"parse": []})
        self.assertNotIn("tok_", p.stdout + p.stderr)

    def test_refuses_event_without_token(self):
        d = tempfile.mkdtemp()
        ev = os.path.join(d, "ev.json")
        discord_event(ev, card(), token="")
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "discord_reply.py"),
                            "--event", ev, "--reply", os.path.join(d, "r.md")],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 1)


if __name__ == "__main__":
    unittest.main()
