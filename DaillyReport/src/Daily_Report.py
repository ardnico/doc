#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from datetime import datetime as dt
import os

with open("config.txt", "r", encoding="utf-8") as f:
    data = f.read().split("\n")

for line in data:
    if line.startswith("name:"):
        name = line.split(":", 1)[1].strip()

today = dt.now()
this_month = today.strftime("%Y-%m")
today_str = today.strftime("%Y-%m-%d")
today_d = today.strftime("%d")
today_of_week = today.strftime("%a")

curdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
month_dir = os.path.join(curdir, "report", this_month)
month_dir_w = os.path.join(month_dir, "work_time")

util_dirss = os.path.join(curdir,"report","utils")

os.makedirs(util_dirss, exist_ok=True)

logdir = os.path.join(curdir, "logs")
if not os.path.exists(logdir):
    os.makedirs(logdir,exist_ok=True)

def write_log( msg: str):
    log_path = os.path.join(logdir, f"{today.strftime('%Y-%m')}_log.txt")
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(f"{dt.now().strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")

if not os.path.exists(month_dir):
    os.makedirs(month_dir_w,exist_ok=True)
    write_log(f"Created directory: {month_dir} and {month_dir_w}")
    
# 直近のタスク記録
CurrentTaskPath = os.path.join(util_dirss,"CurrentTask.adoc")

if not os.path.exists(CurrentTaskPath):
    open(CurrentTaskPath,"w", encoding="utf-8").write("""== 現在のタスク

[cols="3,1,1,2",options="header"]
|===
| タスク名 | 期限 | 状態 | 備考
|===
""")
    write_log(f"Created file: {CurrentTaskPath}")

# 直近の予定記録
CurrentSchedulePath = os.path.join(util_dirss,"CurrentSchedule.adoc")

if not os.path.exists(CurrentSchedulePath):
    open(CurrentSchedulePath,"w", encoding="utf-8").write("""== 直近の予定

[cols="1,3,2",options="header"]
|===
| 日付 | 予定名  | 備考
|===
""")
    write_log(f"Created file: {CurrentSchedulePath}")

reguler_csv_path = os.path.join(util_dirss,"reguler_schedule.csv")

if not os.path.exists(reguler_csv_path):
    open(reguler_csv_path,"w").write("day_of_week,name,time\n")
    write_log(f"Created file: {reguler_csv_path}")

reguler_data = open(reguler_csv_path,"r",encoding="utf-8").read().split("\n")

reguler_line = ""
reguler_line2 = ""

for line in reguler_data:
    if line.startswith(today_of_week):
        reguler_line += f",{line.split(',')[1]},{line.split(',')[2]}\n"
        reguler_line2 += f"== {line.split(',')[1]} \n\n"

base_txt = f"""= 日報
:author: {name}
:revdate: {today_str}
:doctype: article
:icons: font
:toc: macro
:sectnums:

include::../utils/CurrentTask.adoc[]

include::../utils/CurrentSchedule.adoc[]

{reguler_line2}

== 業務内容(Template)
* 現在
* 完了
* 課題

== コメント・所感
// 感想や気づき、チームへの共有事項など自由記述

""".replace("\n\n", "\n")

daily_report_path = os.path.join(month_dir, f"{today_d}_daily_report.adoc")
if not os.path.exists(daily_report_path):
    open(daily_report_path, "w", encoding="utf-8").write(base_txt)

csv_txt = f"""species,task,time
{reguler_line}
"""

dilly_work_time_log_path = os.path.join(month_dir_w, f"{today_str}_work_time_log.csv")

if not os.path.exists(dilly_work_time_log_path):
    open(dilly_work_time_log_path, "w", encoding="utf-8").write(csv_txt)
write_log(f"Created daily report and work time log for {today_str}")

print("Daily report and work time log created successfully.")
