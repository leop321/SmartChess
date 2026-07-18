#!/usr/bin/env python3
"""
PGN Importer für das Eröffnungsbuch.

Dieses Skript liest eine PGN-Datei ein und iteriert über alle Partien und Züge.
Für jede Stellung wird der FEN-String generiert, auf die ersten 4 Felder
normalisiert (wie im OpeningBookService) und der vom Spieler ausgeführte Zug im
UCI-Format extrahiert.

Diese Daten werden dann in die angegebene opening_book.json-Datei unter der
gewünschten bot_id gespeichert. Bereits existierende FENs werden überschrieben.

Voraussetzungen:
- pip install chess

Verwendung:
    python pgn_importer.py <pfad_zur_pgn> <bot_id> [--book-file <pfad_zur_json>]
Beispiel:
    python pgn_importer.py my_games.pgn bot_800_chaotic --book-file opening_book/opening_book.json
"""

import argparse
import json
import os
import sys

try:
    import chess
    import chess.pgn
except ImportError:
    print("Fehler: Das Modul 'chess' ist nicht installiert.")
    print("Bitte installiere es mit: pip install chess")
    sys.exit(1)


def normalize_fen(fen: str) -> str:
    """
    Normalisiert eine FEN-Zeichenkette auf die ersten 4 Felder.
    Dadurch werden Halbzug- und Vollzugzähler ignoriert.
    """
    fields = fen.strip().split()
    if len(fields) < 4:
        raise ValueError(f"Ungültige FEN (weniger als 4 Felder): '{fen}'")
    return " ".join(fields[:4])


def main():
    parser = argparse.ArgumentParser(description="Import PGN games into opening_book.json")
    parser.add_argument("pgn_file", help="Pfad zur PGN-Datei")
    parser.add_argument("bot_id", help="Bot-ID (z. B. 'bot_800_chaotic')")
    parser.add_argument(
        "--book-file", 
        default="opening_book/opening_book.json", 
        help="Pfad zur opening_book.json (Standard: opening_book/opening_book.json)"
    )

    args = parser.parse_args()

    # 1. PGN-Datei prüfen
    if not os.path.isfile(args.pgn_file):
        print(f"Fehler: PGN-Datei '{args.pgn_file}' nicht gefunden.")
        sys.exit(1)

    # 2. Bestehendes JSON-Eröffnungsbuch laden
    book = {}
    if os.path.isfile(args.book_file):
        with open(args.book_file, "r", encoding="utf-8") as f:
            try:
                book = json.load(f)
            except json.JSONDecodeError:
                print(f"Fehler: '{args.book_file}' ist keine gültige JSON-Datei. Erstelle neu.")
                book = {}
    else:
        print(f"Hinweis: '{args.book_file}' existiert nicht. Wird neu erstellt.")

    # 3. Sicherstellen, dass der Key für die Bot-ID existiert
    if args.bot_id not in book:
        book[args.bot_id] = {}

    bot_book = book[args.bot_id]
    moves_added = 0
    games_processed = 0

    # 4. PGN parsen und Züge extrahieren
    with open(args.pgn_file, "r", encoding="utf-8") as pgn_handle:
        while True:
            # Lese die nächste Partie
            game = chess.pgn.read_game(pgn_handle)
            if game is None:
                break
            
            games_processed += 1
            board = game.board()
            
            # Iteriere über die Züge der Hauptvariante
            for move in game.mainline_moves():
                # FEN der aktuellen Stellung generieren (vor Ausführung des Zuges)
                fen = board.fen()
                norm_fen = normalize_fen(fen)
                
                # Zug im UCI-Format
                uci_move = move.uci()
                
                # FEN zu UCI Mapping hinzufügen (überschreibt bestehende Züge)
                bot_book[norm_fen] = uci_move
                moves_added += 1
                
                # Zug auf dem Board ausführen, um nächste Stellung zu erreichen
                board.push(move)

    # 5. Aktualisiertes Eröffnungsbuch speichern
    # Verzeichnisse anlegen falls nötig
    os.makedirs(os.path.dirname(os.path.abspath(args.book_file)), exist_ok=True)
    
    with open(args.book_file, "w", encoding="utf-8") as f:
        json.dump(book, f, indent=2)

    print(f"Erfolgreich! {games_processed} Partie(n) verarbeitet.")
    print(f"{moves_added} Stellungs-Mappings für Bot '{args.bot_id}' in '{args.book_file}' gespeichert.")


if __name__ == "__main__":
    main()
