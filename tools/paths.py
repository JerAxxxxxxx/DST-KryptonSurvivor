"""Shared paths. Set DST_GAME_DIR or pass --game-dir for another installation."""
from pathlib import Path
import argparse
import os
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'build/art'
PREVIEWS=ROOT/'build/previews'
MOD=ROOT/'mod'

def game_anim_dir():
    parser=argparse.ArgumentParser()
    parser.add_argument('--game-dir',type=Path,default=Path(os.environ.get('DST_GAME_DIR',r"D:\SteamLibrary\steamapps\common\Don't Starve Together")))
    args=parser.parse_args()
    path=args.game_dir/'data/anim'
    if not (path/'wilson.zip').is_file():
        parser.error('DST data/anim was not found. Set DST_GAME_DIR or pass --game-dir.')
    return path
