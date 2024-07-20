#!/usr/bin/env python3

# output gpio settings from environment files in a Github markdown table

# @author godmar@gmail.com

import glob
from datetime import datetime
from functools import reduce

today = datetime.now().astimezone().strftime("%Y:%m:%d %H:%M:%S %Z %z")

envdir = "environment/"
model2settings = {}
for file in glob.glob(f"{envdir}*.uenv.txt"):
    model = file.replace(envdir, "").replace(".uenv.txt", "")
    with open(file, "r") as env_file:
        settings = dict(map(lambda l : tuple(l.split("=", 1)), 
                    filter(lambda s: s.strip() != "", env_file.read().split("\n"))))
        model2settings[model] = settings

labels =  reduce(set.union, map(lambda k : set(k.keys()), model2settings.values()))
exclude = ["gpio_default"]
gpiolabels = list(sorted(filter(lambda l: l.startswith("gpio_") and l not in exclude, labels)))

print (f'# Thingino GPIO assignments as of {today}')
print ()
headings = "|".join(map(lambda s : s.replace("gpio_", ""), gpiolabels))
print (f'| Model | {headings}')
print (f'|{" --- |" * (len(gpiolabels) + 1)}')
for model, settings in sorted(model2settings.items()):
    print (f'| {model } |{" | ".join(settings[k] if k in settings else "" for k in gpiolabels)}|')
