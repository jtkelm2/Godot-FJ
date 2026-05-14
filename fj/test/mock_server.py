#!/usr/bin/env python3
"""Minimal TCP mock server for testing the FJ Godot client.

Run this, then launch the Godot client and connect to 127.0.0.1:9001.
Messages are sent automatically on a timer after the client connects.
"""

import socket
import json
import time
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9001

SEQUENCE = [
    # catalog (flat slot format)
    {
        "type": "catalog",
        "cards": {
            "enemy_3": {"name": "enemy_3", "display_name": "Enemy (3)", "text": "If you kill this with a weapon: Discard this and your kill pile.", "level": 3, "types": ["ENEMY"], "is_elusive": False, "is_first": False},
            "enemy_5": {"name": "enemy_5", "display_name": "Enemy (5)", "text": "", "level": 5, "types": ["ENEMY"], "is_elusive": False, "is_first": False},
            "food_5": {"name": "food_5", "display_name": "Food (5)", "text": "", "level": 5, "types": ["FOOD"], "is_elusive": False, "is_first": False},
            "weapon_4": {"name": "weapon_4", "display_name": "Weapon (4)", "text": "", "level": 4, "types": ["WEAPON"], "is_elusive": False, "is_first": False},
            "weapon_2": {"name": "weapon_2", "display_name": "Weapon (2)", "text": "", "level": 2, "types": ["WEAPON"], "is_elusive": False, "is_first": False},
            "major_1": {"name": "major_1", "display_name": "The Magician", "text": "On resolve: Look at the top 3 cards of the deck, and resolve one of them.", "level": None, "types": ["EVENT"], "is_elusive": False, "is_first": False},
            "good_role_1": {"name": "good_role_1", "display_name": "Human", "text": "Good role. While equipped: Call the Guards.", "level": None, "types": ["EQUIPMENT"], "is_elusive": False, "is_first": False},
        },
        "slots": {
            "red_hand":                         {"owner": "self",     "role": "hand"},
            "red_deck":                         {"owner": "self",     "role": "deck"},
            "red_refresh":                      {"owner": "self",     "role": "refresh"},
            "red_discard":                      {"owner": "self",     "role": "discard"},
            "red_sidebar":                      {"owner": "self",     "role": "sidebar"},
            "red_equipment":                    {"owner": "self",     "role": "equipment"},
            "red_action_field_top_distant":      {"owner": "self",     "role": "action_field_top_distant"},
            "red_action_field_top_hidden":       {"owner": "self",     "role": "action_field_top_hidden"},
            "red_action_field_bottom_hidden":    {"owner": "self",     "role": "action_field_bottom_hidden"},
            "red_action_field_bottom_distant":   {"owner": "self",     "role": "action_field_bottom_distant"},
            "red_ws_0_weapon":                  {"owner": "self",     "role": "ws_0_weapon"},
            "red_ws_0_killstack":               {"owner": "self",     "role": "ws_0_killstack"},
            "blue_deck":                        {"owner": "opponent", "role": "deck"},
            "blue_action_field_top_distant":     {"owner": "opponent", "role": "action_field_top_distant"},
            "blue_action_field_bottom_distant":  {"owner": "opponent", "role": "action_field_bottom_distant"},
            "guard_deck":                       {"owner": "shared",   "role": "guard_deck"},
        },
        "weapon_slots": {
            "red_ws_0":  {"owner": "self",     "role": "ws_0"},
            "blue_ws_0": {"owner": "opponent", "role": "ws_0"},
        }
    },

    # state (identity via view.role/alignment; opponent hidden slots absent)
    {
        "type": "state",
        "view": {
            "role": "Human",
            "alignment": "GOOD",
            "hp": 20,
            "slots": {
                "red_hand": [{"name": "food_5", "counters": 0}, {"name": "enemy_3", "counters": 0}, {"name": "weapon_2", "counters": 0}],
                "red_deck": 25,
                "red_refresh": 0,
                "red_discard": 0,
                "red_equipment": [{"name": "good_role_1", "counters": 0}],
                "red_action_field_top_distant": [{"name": "enemy_5", "counters": 0}],
                "red_action_field_top_hidden": [{"name": "major_1", "counters": 0}],
                "red_action_field_bottom_hidden": [{"name": "weapon_4", "counters": 0}],
                "red_action_field_bottom_distant": [{"name": "enemy_3", "counters": 0}],
                "red_ws_0_weapon": [],
                "red_ws_0_killstack": [],
                "blue_deck": 24,
                "blue_action_field_top_distant": [{"name": "enemy_3", "counters": 0}],
                "blue_action_field_bottom_distant": [{"name": "food_5", "counters": 0}],
                "guard_deck": 4,
            },
            "current_phase": "ACTION",
            "priority": "RED",
            "game_result": None
        }
    },

    # prompt
    {
        "type": "prompt",
        "text": "Choose an action slot to resolve:",
        "options": [
            {"type": "card", "slot": "red_action_field_top_distant", "index": 0},
            {"type": "card", "slot": "red_action_field_top_hidden", "index": 0},
            {"type": "card", "slot": "red_action_field_bottom_hidden", "index": 0},
            {"type": "card", "slot": "red_action_field_bottom_distant", "index": 0},
            {"type": "text", "text": "Pass"}
        ]
    },

    # close
    {"type": "close"},
]

def send_msg(conn, msg):
    data = json.dumps(msg) + "\n"
    conn.sendall(data.encode("utf-8"))
    print(f">>> [{msg['type']}]")

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(1)
    print(f"Mock server listening on port {PORT}...")

    conn, addr = srv.accept()
    print(f"Client connected from {addr}")

    # Send messages with delays
    for i, msg in enumerate(SEQUENCE):
        time.sleep(0.5)
        send_msg(conn, msg)

    # Listen for responses
    print("Waiting for client responses...")
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                print("Client disconnected")
                break
            for line in data.decode("utf-8").strip().split("\n"):
                if line:
                    parsed = json.loads(line)
                    print(f"<<< {json.dumps(parsed, indent=2)}")
    except KeyboardInterrupt:
        pass
    finally:
        conn.close()
        srv.close()
        print("Server stopped")

if __name__ == "__main__":
    main()
