#!/usr/bin/env python3
"""Mock server that exercises the `events` field of state messages.

Sends an initial state, waits 2s, then sends a follow-up state with a
card_moved event so the client should animate a card flying from
red_action_field_top_distant → red_discard.

Run on port 9001; the Godot client should connect to 127.0.0.1:9001.
"""

import socket, json, sys, time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9001

CATALOG = {
    "type": "catalog",
    "cards": {
        "enemy_3":  {"name": "enemy_3",  "display_name": "Enemy (3)", "text": "", "level": 3, "types": ["ENEMY"],  "is_elusive": False, "is_first": False},
        "enemy_5":  {"name": "enemy_5",  "display_name": "Enemy (5)", "text": "", "level": 5, "types": ["ENEMY"],  "is_elusive": False, "is_first": False},
        "food_5":   {"name": "food_5",   "display_name": "Food (5)",  "text": "", "level": 5, "types": ["FOOD"],   "is_elusive": False, "is_first": False},
        "weapon_2": {"name": "weapon_2", "display_name": "Weapon (2)","text": "", "level": 2, "types": ["WEAPON"], "is_elusive": False, "is_first": False},
    },
    "slots": {
        "red_hand":                        {"owner": "self",  "role": "hand"},
        "red_deck":                        {"owner": "self",  "role": "deck"},
        "red_discard":                     {"owner": "self",  "role": "discard"},
        "red_action_field_top_distant":    {"owner": "self",  "role": "action_field_top_distant"},
        "red_ws_0_weapon":                 {"owner": "self",  "role": "ws_0_weapon"},
        "red_ws_0_killstack":              {"owner": "self",  "role": "ws_0_killstack"},
        "blue_deck":                       {"owner": "opponent", "role": "deck"},
    },
    "weapon_slots": {
        "red_ws_0":  {"owner": "self",     "role": "ws_0"},
        "blue_ws_0": {"owner": "opponent", "role": "ws_0"},
    },
}

STATE_INIT = {
    "type": "state",
    "view": {
        "role": "Human",
        "alignment": "GOOD",
        "hp": 20,
        "slots": {
            "red_hand": [{"name": "food_5", "counters": 0}, {"name": "weapon_2", "counters": 0}],
            "red_deck": 25,
            "red_discard": 0,
            "red_action_field_top_distant": [{"name": "enemy_5", "counters": 0}],
            "red_ws_0_weapon": [],
            "red_ws_0_killstack": [],
            "blue_deck": 24,
        },
        "current_phase": "ACTION",
        "priority": "RED",
        "game_result": None,
    },
}

# Move enemy_5 from action field to discard. Discard count goes 0 → 1; action
# field top goes [enemy_5] → [].
STATE_AFTER_MOVE = {
    "type": "state",
    "view": {
        "role": "Human",
        "alignment": "GOOD",
        "hp": 18,
        "slots": {
            "red_hand": [{"name": "food_5", "counters": 0}, {"name": "weapon_2", "counters": 0}],
            "red_deck": 25,
            "red_discard": 1,
            "red_action_field_top_distant": [],
            "red_ws_0_weapon": [],
            "red_ws_0_killstack": [],
            "blue_deck": 24,
        },
        "current_phase": "ACTION",
        "priority": "RED",
        "game_result": None,
    },
    "events": [
        {"type": "card_moved", "source": "red_action_field_top_distant", "source_index": 0, "dest": "red_discard", "dest_index": 0},
        {"type": "hp_changed", "old": 20, "new": 18},
    ],
}

CLOSE = {"type": "close"}

def send(conn, msg):
    conn.sendall((json.dumps(msg) + "\n").encode("utf-8"))
    print(f">>> {msg.get('type')}")

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(1)
    print(f"Mock-events listening on port {PORT}...")
    conn, addr = srv.accept()
    print(f"Client connected from {addr}")

    for msg in [CATALOG, STATE_INIT]:
        send(conn, msg); time.sleep(0.4)

    print("Waiting 2s before sending the events-bearing state...")
    time.sleep(2.0)
    send(conn, STATE_AFTER_MOVE)

    time.sleep(2.0)
    send(conn, CLOSE)
    print("Done. Press Ctrl-C to exit.")
    try:
        while True:
            data = conn.recv(4096)
            if not data: break
            print(f"<<< {data.decode('utf-8').strip()}")
    except (KeyboardInterrupt, ConnectionResetError):
        pass
    finally:
        conn.close()
        srv.close()

if __name__ == "__main__":
    main()
