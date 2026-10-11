-- Generated from assets/slices.json by tools/build_eating_assets.py.
return {
    build = "krypton_eating_build",
    frames_per_second = 30,
    symbols = {
        open = "krypton_eat_open",
        chew = "krypton_eat_chew",
        satisfied = "krypton_eat_satisfied",
    },
    timelines = {
        eat_pre = { { frame = 0, pose = "open" } },
        eat_lag = { { frame = 0, pose = "open" } },
        eat = { { frame = 0, pose = "open" }, { frame = 12, pose = "chew" }, { frame = 18, pose = "open" }, { frame = 24, pose = "chew" }, { frame = 30, pose = "open" }, { frame = 36, pose = "chew" }, { frame = 42, pose = "open" }, { frame = 48, pose = "chew" }, { frame = 54, pose = "open" }, { frame = 60, pose = "chew" }, { frame = 66, pose = "satisfied" }, { frame = 77, pose = "open" }, { frame = 83, pose = "chew" }, { frame = 87, pose = "satisfied" } },
        quick_eat_pre = { { frame = 6, pose = "open" } },
        quick_eat_lag = { { frame = 0, pose = "open" } },
        quick_eat = { { frame = 0, pose = "open" }, { frame = 4, pose = "chew" }, { frame = 9, pose = "satisfied" } },
        quick_drink_pre = { { frame = 3, pose = "open" } },
        quick_drink_lag = { { frame = 0, pose = "open" } },
        quick_drink = { { frame = 0, pose = "open" }, { frame = 13, pose = "satisfied" } },
    },
}
